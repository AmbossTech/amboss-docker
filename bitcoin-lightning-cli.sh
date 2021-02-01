#!/bin/bash

docker exec amboss_clightning_bitcoin lightning-cli --rpc-file /root/.lightning/lightning-rpc "$@"
