#!/bin/bash

set -e

ssh -t cloud-user@10.3.11.94 'cd ~/developer.redhat.com && ./bootstrap.sh'
ssh -t cloud-user@10.3.11.94 'cd ~/developer.redhat.com && ./setup_containers.sh'

