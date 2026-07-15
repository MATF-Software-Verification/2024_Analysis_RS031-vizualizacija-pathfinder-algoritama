#!/usr/bin/env bash
# What: Reproduces the QtTest unit/integration test run and gcov/lcov coverage report.
# Why:  Single entry point so a reviewer can regenerate every test + coverage artifact.
# How:  Configures CMake (coverage instrumentation on), builds the serverlogic lib and
#       the five test executables, runs them headless (offscreen Qt platform), then
#       captures coverage with lcov, filters to the analyzed server sources, and emits
#       both an HTML report and a plain-text summary under results/.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="${HERE}/build"
RESULTS="${HERE}/results"
# The analyzed sources live in the submodule; coverage is reported only for these.
# Canonicalize: lcov --extract matches the absolute paths gcov stored, which have no "..".
SERVER_DIR="$(realpath "${HERE}/../SketchIt/SketchIt/server")"

# Qt prefix can be overridden; default matches the documented install location.
QT_PREFIX="${QT_PREFIX:-/home/jovan/Qt/6.10.2/gcc_64}"

echo "==> Ensuring the build fix (custom.patch) is applied to the submodule"
( cd "${HERE}/.." && git -C SketchIt apply --check custom.patch 2>/dev/null \
    && git -C SketchIt apply custom.patch \
    && echo "    custom.patch applied" \
    || echo "    custom.patch already applied (or not needed) - continuing" )

echo "==> Configuring"
cmake -S "${HERE}" -B "${BUILD}" \
    -DCMAKE_PREFIX_PATH="${QT_PREFIX}" \
    -DENABLE_COVERAGE=ON >/dev/null

echo "==> Building"
cmake --build "${BUILD}" -j"$(nproc)" >/dev/null

echo "==> Zeroing coverage counters"
lcov --directory "${BUILD}" --zerocounters >/dev/null 2>&1 || true

echo "==> Running tests (headless)"
export QT_QPA_PLATFORM=offscreen
ctest --test-dir "${BUILD}" --output-on-failure

echo "==> Capturing coverage"
mkdir -p "${RESULTS}"
# --ignore-errors: lcov 2.0 otherwise aborts on benign gcov/geninfo warnings coming
# from inlined libstdc++ template code (mismatched exception tags, unexecuted blocks).
LCOV_IGNORE="mismatch,gcov,unused,negative,empty"
lcov --capture --directory "${BUILD}" \
     --output-file "${RESULTS}/coverage.info" \
     --rc branch_coverage=1 \
     --ignore-errors "${LCOV_IGNORE}" >/dev/null 2>&1

# Keep only the analyzed server sources (drop Qt headers, autogen, test files).
lcov --extract "${RESULTS}/coverage.info" "${SERVER_DIR}/*" \
     --output-file "${RESULTS}/coverage.server.info" \
     --ignore-errors "${LCOV_IGNORE}" >/dev/null 2>&1

# Per-file summary straight from gcov. We deliberately do NOT use `lcov --list`
# here: lcov 2.0's text table reports a misleading per-file rate for this project
# (it disagrees with both gcov and the genhtml HTML it generates from the same data).
# gcov is the ground truth, so we drive the summary from it.
echo "==> Per-file line coverage (analyzed sources, via gcov):"
GCDA_DIR="${BUILD}/CMakeFiles/serverlogic.dir${SERVER_DIR}"
{
    printf '%-18s %8s %10s\n' "file" "lines" "executed"
    for f in points hangman words leaderboard manager player game; do
        line=$(gcov -n -o "${GCDA_DIR}" "${GCDA_DIR}/${f}.cpp.gcda" 2>/dev/null \
               | grep -A1 "${f}.cpp" | grep "Lines executed" | head -1)
        pct=${line#*:}; pct=${pct%% *}
        tot=${line##*of }
        printf '%-18s %8s %9s%%\n' "${f}.cpp" "${tot}" "${pct%\%}"
    done
} | tee "${RESULTS}/coverage.summary.txt"

echo "==> Generating HTML report"
genhtml "${RESULTS}/coverage.server.info" \
        --output-directory "${RESULTS}/html" >/dev/null 2>&1

echo "==> Done. Open ${RESULTS}/html/index.html for the full report."
