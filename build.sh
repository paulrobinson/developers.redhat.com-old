#!/bin/bash

set -e

source _ci.sh

setup_environment

$RVMDO rake clean[all] deploy[production,0.0-build-1]

