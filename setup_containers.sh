#!/bin/bash

set -e

cd _docker
sudo ./control.sh -b
sudo ./control.sh -r

#Wait for them to be ready. Should check the status of all containers. Currently just does the slowest one.
STATUS=$(sudo docker wait docker_searchiskoconfigure_1)
if [ "$STATUS" != 0 ]; then
	echo Error booting Containers
	exit 1
fi
echo CONTAINERS READY!
