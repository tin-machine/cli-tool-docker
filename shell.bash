#!/bin/bash

PATH=$PATH:~/.rd/bin

nerdctl \
  run \
    --privileged \
    --network host \
    --volume $HOME:$HOME \
    --user 0:0 \
    -it \
      cli-tool-docker sh -c \
        "hostname $(hostname) && \
        useradd \
          --uid $(id -u) \
          --gid $(id -g) \
	        --home $HOME \
	        --shell /usr/bin/fish \
	        $USER 2> /dev/null && \
        echo '${USER} ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/$USER && \
	      su - $USER"
