#!/usr/bin/env bash
# Kept so that the documented clone-and-run flow keeps working.
# Everything lives in bin/dot now; see `bin/dot help`.
exec "$(dirname -- "${BASH_SOURCE[0]}")/bin/dot" install "$@"
