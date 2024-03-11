#!/bin/bash

/usr/local/bin/nerdctl \
  run \
    --network host \
    --rm \
    -it \
    --volume $HOME:$HOME \
    --env HOME=${HOME} \
    -w ${HOME} \
    cli-tool-docker \
    fish -l
