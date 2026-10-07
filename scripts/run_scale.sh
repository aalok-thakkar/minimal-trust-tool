#!/bin/sh
# Experiment E3 (scale) and the gadget validity check.
#   scripts/run_scale.sh            full run (hours); results/ and results/scale_run.log
#   scripts/run_scale.sh --quick    smoke test (< 1 min); results/quick/
# Keep the machine otherwise idle: the timing phase runs one child at a time.
set -e
cd "$(dirname "$0")/.."
eval "$(opam env --switch=5.1.0 2>/dev/null)" || true
dune build --profile release
exec ./_build/default/bin/main.exe scale "$@"
