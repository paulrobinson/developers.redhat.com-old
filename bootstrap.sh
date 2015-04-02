#!/bin/bash

set -e

# First stop the Docker container. Needs to be done before the git update so as to stop the current configuration
cd _docker
sudo ./control.sh -s

# Update the repo
git fetch paulrobinson
git checkout RHD-133
git pull --rebase paulrobinson RHD-133


