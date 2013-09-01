#!/bin/bash

set -e

echo "----> Generating exports"
etc/list-exports/list-exports list_all

echo "----> Generating rockspecs"
rockspec/gen-rockspecs

echo "----> Removing a rock"
sudo luarocks remove --force le-dsl-fsm || true

echo "----> Making a rock"
sudo luarocks make rockspec/le-dsl-fsm-scm-1.rockspec

echo "----> OK"
