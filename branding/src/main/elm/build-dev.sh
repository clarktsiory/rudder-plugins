#!/bin/sh

ELM_DIR="$( cd "$( dirname "$0" )" && pwd )"
cd $ELM_DIR

./build.sh
cp generated/* ../../../target/classes/toserve/branding
