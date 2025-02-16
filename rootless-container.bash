#!/bin/bash

# strace -f -o ~/nerdctl.log /usr/local/bin/nerdctl \
sudo /usr/local/bin/nerdctl \
  run --rm -it \
    --network host \
    --ipc shareable \
    --volume $HOME:$HOME \
    --env HOME=${HOME} \
    --env UID=$(id -u) \
    --env GID=$(id -g) \
    --env USER_NAME=$(whoami) \
    -w ${HOME} \
    --privileged \
    --cpus 6 \
    --init \
      ghcr.io/tin-machine/cli-tool-docker:latest /usr/bin/fish
