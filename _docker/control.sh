#!/bin/bash

build=false
restart=false
stop=false

function show_help() {
  echo "
Shortcuts to control Docker containers\n
    -b      Build the containers
    -r      Restart the containers
    -s      Stop the containers
    -h / -? Show this help message
"
}

OPTIND=1         # Reset in case getopts has been used previously in the shell.
while getopts "h?brs" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 0
        ;;
    b)  build=true
        ;;
    r)  restart=true
        ;;
    s)  stop=true
        ;;
    esac
done

shift $((OPTIND-1))

if [ $build = true ]; then
  docker build --tag developer.redhat.com/base ./base
  docker build --tag developer.redhat.com/java ./java
  docker-compose build
fi

if [ $restart = true ]; then
  docker-compose kill 
  docker-compose up -d
fi

if [ $stop = true ]; then
  docker-compose kill
fi
