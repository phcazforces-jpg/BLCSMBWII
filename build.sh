#!/usr/bin/env bash
set -e
exec "$(dirname "$0")/projects/nsmbw/tools/build-linux.sh" "$@"
