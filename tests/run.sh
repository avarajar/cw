#!/usr/bin/env bash
# runs the whole bats suite against a throwaway CW_HOME
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$here/bats/bin/bats" "$@" "$here"/*.bats
