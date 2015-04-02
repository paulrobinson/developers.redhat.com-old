#!/bin/bash

set -e

cd _docker
sudo ./control.sh -b
sudo ./control.sh -r

