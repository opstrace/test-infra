#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR

# Get 7-character commit SHA (note: doesn't detect dirty commits)
COMMIT_SHA=$(git rev-parse HEAD | cut -b 1-7)

docker build -t opstrace/avalanche-rollout:${COMMIT_SHA} .
