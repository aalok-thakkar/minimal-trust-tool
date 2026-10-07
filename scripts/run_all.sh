#!/bin/sh
# Run every experiment of the paper in sequence into results/final/.
#   scripts/run_all.sh            (hours; keep the machine otherwise idle)
# Order: correctness checks, analyser rows (E1/E2/E6/E7), CPSA rows (E1/E2/E4),
# scale counts (parallel) and gadget check (E3), scale timing (sequential), and the
# open-ended bound sensitivity study (E5) last. Load average is logged around each step.
set -eu
cd "$(dirname "$0")/.."
eval "$(opam env --switch=5.1.0 2>/dev/null)" || true
OUT=results/final
mkdir -p "$OUT"
LOG="$OUT/run_all.log"
step() {
  name=$1; shift
  echo "== $name start $(date '+%F %T') load: $(uptime | sed 's/.*load averages*: //')" | tee -a "$LOG"
  if "$@" >> "$OUT/$name.stdout" 2>&1; then status=ok; else status="FAILED($?)"; fi
  echo "== $name end   $(date '+%F %T') load: $(uptime | sed 's/.*load averages*: //') status: $status" | tee -a "$LOG"
}
{
  echo "machine: $(sysctl -n machdep.cpu.brand_string), $(sysctl -n hw.ncpu) cores, $(($(sysctl -n hw.memsize) / 1073741824)) GB"
  echo "os: $(sw_vers -productName) $(sw_vers -productVersion)"
  echo "ocaml: $(ocaml -version)"; echo "dune: $(dune --version)"
  echo "cpsa: $(~/.local/bin/cpsa4 --version 2>&1 | head -1)"
  echo "sources sha256: $(find lib bin test cpsa/protocols -type f \( -name '*.ml' -o -name '*.mli' -o -name '*.scm' -o -name dune \) | sort | xargs cat | shasum -a 256 | cut -d' ' -f1)"
  echo "started: $(date '+%F %T')"
} > "$OUT/manifest.txt"

dune build --profile release 2>&1 | tee "$OUT/build.log"
step tests        dune test --force --profile release
step diff_core    sh test/diff_python.sh
step diff_bounded sh test/diff_bounded.sh
step rows         ./_build/default/bin/exp/exp.exe rows     --out "$OUT"
step channels     ./_build/default/bin/exp/exp.exe channels --out "$OUT"
step compose      ./_build/default/bin/exp/exp.exe compose  --out "$OUT"
step cpsa         ./_build/default/bin/main.exe cpsa        --out "$OUT"
step diff_cpsa    python3 -B test/diff_cpsa.py "$OUT/cpsa_rows.csv"
step scale_counts ./_build/default/bin/main.exe scale --phase counts,gadget --jobs 10 --out "$OUT"
step scale_timing ./_build/default/bin/main.exe scale --phase timing --out "$OUT"
step bound        ./_build/default/bin/exp/exp.exe bound    --out "$OUT"
echo "finished: $(date '+%F %T')" >> "$OUT/manifest.txt"
