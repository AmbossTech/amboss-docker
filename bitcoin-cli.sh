#!/bin/bash

docker exec amboss_bitcoind bitcoin-cli -datadir="/data" "$@"
