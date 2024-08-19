#!/usr/bin/env bash

set -e

vault_file_path=$1
if [ -z $vault_file_path ]; then
    echo You need to provide vault file path as the first argument. None received.
    exit 2
fi

ansible-vault decrypt --output - $vault_file_path
