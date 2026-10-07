#!/bin/sh
# Differential test of Bounded/Protocols against the Python prototype (reference/python).
# Compares, per protocol row and witness mode, the oracle answer (verdict, stopping set,
# states expanded where comparable) at every trust, and Algorithm 1's W, H and call
# counts with and without shrinking. Usage: test/diff_bounded.sh (run from the repository root).
set -eu
cd "$(dirname "$0")/.."
ARTIFACT=reference/python
TMP=${TMPDIR:-/tmp}/trust-diff-bounded.$$
mkdir -p "$TMP"
dune build --profile release test/diff_bounded.exe
./_build/default/test/diff_bounded.exe | sort > "$TMP/ml.txt"
python3 -B test/diff_driver_bounded.py "$ARTIFACT" | sort > "$TMP/py.txt"
if diff "$TMP/py.txt" "$TMP/ml.txt"; then
  echo "diff_bounded: $(wc -l < "$TMP/ml.txt") lines identical"
  rm -rf "$TMP"
else
  echo "diff_bounded: DIFFERENCES (python <, ocaml >); files kept in $TMP"
  exit 1
fi
