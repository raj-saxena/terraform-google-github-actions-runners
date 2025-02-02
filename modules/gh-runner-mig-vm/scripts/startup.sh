#!/bin/bash
# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#install jq
apt-get update
apt-get -y install jq

secretUri=$(curl -sS "http://metadata.google.internal/computeMetadata/v1/instance/attributes/secret-id" -H "Metadata-Flavor: Google")
#secrets URI is of the form projects/$PROJECT_NUMBER/secrets/$SECRET_NAME/versions/$SECRET_VERSION
#split into array based on `/` delimeter
IFS="/" read -r -a secretsConfig <<<"$secretUri"
#get SECRET_NAME and SECRET_VERSION
SECRET_NAME=${secretsConfig[3]}
SECRET_VERSION=${secretsConfig[5]}
#access secret from secretsmanager
secrets=$(gcloud secrets versions access "$SECRET_VERSION" --secret="$SECRET_NAME")
#set secrets as env vars
# shellcheck disable=SC2046
# we want to use wordsplitting
export $(echo "$secrets" | jq -r "to_entries|map(\"\(.key)=\(.value|tostring)\")|.[]")
#github runner version
GH_RUNNER_VERSION="2.283.2"
#get actions binary
curl -o actions.tar.gz --location "https://github.com/actions/runner/releases/download/v${GH_RUNNER_VERSION}/actions-runner-linux-x64-${GH_RUNNER_VERSION}.tar.gz"

# Register runner
install_runner() {
    COUNT=$1
    RUNNER_DIR="/runner-$COUNT"
    RUNNER_TEMP_DIR="$RUNNER_DIR/tmp"
    RUNNER_NAME="$HOSTNAME-$COUNT"
    mkdir -p "$RUNNER_TEMP_DIR"
    tar -zxf actions.tar.gz --directory "$RUNNER_DIR"
    
    "$RUNNER_DIR"/bin/installdependencies.sh
    echo "Registering Github action runner '$RUNNER_NAME'"
    if [[ -z $REPO_NAME ]]; then
        # Add action runner for an organisation
        POST_URL="https://api.github.com/orgs/${REPO_OWNER}/actions/runners/registration-token"
        GH_URL="https://github.com/${REPO_OWNER}"
    else
        # Add action runner for a repo
        POST_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runners/registration-token"
        GH_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}"
    fi

    #get actions token
    ACTIONS_RUNNER_INPUT_TOKEN="$(curl -sS --request POST --url "$POST_URL" --header "authorization: Bearer ${GITHUB_TOKEN}" --header 'content-type: application/json' | jq -r .token)"
    #configure runner
    RUNNER_ALLOW_RUNASROOT=1 "$RUNNER_DIR"/config.sh --unattended --name "$RUNNER_NAME" --replace --work "$RUNNER_TEMP_DIR" --url "$GH_URL" --token "$ACTIONS_RUNNER_INPUT_TOKEN" --labels "$LABELS"

    #install and start runner service
    cd "$RUNNER_DIR" || exit
    ./svc.sh install
    ./svc.sh start
    # exit to previous directory
    cd - || exit
}

# Register configured number of github runners instances
for ((i = 1; i <= GH_RUNNER_INSTANCES_COUNT; i++)); do
    install_runner "$i"
done

rm -f actions.tar.gz