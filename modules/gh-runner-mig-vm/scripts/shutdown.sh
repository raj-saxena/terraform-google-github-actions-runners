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

#stop and uninstall the runner service
uninstall_runner() {
    COUNT=$1
    RUNNER_DIR="/runner-$COUNT"
    RUNNER_NAME="$HOSTNAME-$COUNT"
    cd "$RUNNER_DIR" || exit
    echo "De-registering $RUNNER_NAME"
    ./svc.sh stop
    ./svc.sh uninstall
    if [[ -z $REPO_NAME ]]; then
        # Remove action runner from the organisation
        POST_URL="https://api.github.com/orgs/${REPO_OWNER}/actions/runners/remove-token"
    else
        # Remove action runner from the repo
        POST_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runners/remove-token"
    fi
    #remove the runner configuration
    RUNNER_ALLOW_RUNASROOT=1 "$RUNNER_DIR"/config.sh remove --unattended --name "$RUNNER_NAME" --token "$(curl -sS --request POST --url "$POST_URL" --header "authorization: Bearer ${GITHUB_TOKEN}" --header "content-type: application/json" | jq -r .token)"

    # Cleanup directories
    cd - || exit
    rm -rf "$RUNNER_DIR"
}

# De-register configured number of github runners instances
for ((i = 1; i <= GH_RUNNER_INSTANCES_COUNT; i++)); do
    uninstall_runner "$i"
done
