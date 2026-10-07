#!/bin/sh
# Differential test of the OCaml library against the Python reference.
# Usage: test/diff_python.sh [SEED] [SMALL] [LARGE]   (run from the repository root)
set -eu
cd "$(dirname "$0")/.."
ARTIFACT=reference/python
SEED=${1:-2026}
SMALL=${2:-200}
LARGE=${3:-100}
dune build test/diff_python.exe
python3 test/diff_driver.py "$ARTIFACT" "$SEED" "$SMALL" "$LARGE" \
  | ./_build/default/test/diff_python.exe
