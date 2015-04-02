#!/bin/bash

set -e

git fetch paulrobinson
git checkout RHD-133
git pull --rebase paulrobinson RHD-133


