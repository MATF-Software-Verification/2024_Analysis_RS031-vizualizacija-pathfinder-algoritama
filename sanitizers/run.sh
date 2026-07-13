#!/usr/bin/env bash
# What: Rebuilds the QtTest suite with AddressSanitizer + UndefinedBehaviorSanitizer
#       and runs it, capturing any runtime memory/UB findings.
# Why:  Dynamic analysis catches errors that only manifest at runtime: heap leaks,
#       use-after-free, out-of-bounds, signed overflow, invalid enum/shift, etc.
# How:  Configures the unit_tests CMake project with coverage OFF and the sanitizer
#       flags injected, then runs every test under ASan/UBSan with logging on.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(realpath "${HERE}/..")"
BUILD="${HERE}/build"
RESULTS="${HERE}/results"
mkdir -p "${RESULTS}"

QT_PREFIX="${QT_PREFIX:-/home/jovan/Qt/6.10.2/gcc_64}"
# Besides the default UBSan set we add unsigned-integer-overflow: it is technically
# defined behavior, but it is exactly how the Hangman bug manifests
# (`w.size()*2-1` underflows size_t for an empty word -> huge allocation).
SAN_FLAGS="-fsanitize=address,undefined,unsigned-integer-overflow -fsanitize-recover=unsigned-integer-overflow -fno-omit-frame-pointer -g -O1"

# Use clang++ here: the unsigned-integer-overflow check is a Clang-only sanitizer
# (gcc rejects it). It is also healthy to run the dynamic analysis under a second
# compiler than the gcc used for the coverage build.
CXX_COMPILER="${CXX_COMPILER:-clang++}"

echo "==> Configuring with ASan + UBSan (clang, coverage off)"
cmake -S "${ROOT}/unit_tests" -B "${BUILD}" \
    -DCMAKE_PREFIX_PATH="${QT_PREFIX}" \
    -DCMAKE_CXX_COMPILER="${CXX_COMPILER}" \
    -DENABLE_COVERAGE=OFF \
    -DCMAKE_CXX_FLAGS="${SAN_FLAGS}" \
    -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined" >/dev/null

echo "==> Building"
cmake --build "${BUILD}" -j"$(nproc)" >/dev/null

# halt_on_error=0 lets a test finish so we collect *all* findings, not just the first.
# detect_leaks=1 turns on LeakSanitizer (part of ASan).
export QT_QPA_PLATFORM=offscreen
export ASAN_OPTIONS="detect_leaks=1:halt_on_error=0:log_path=${RESULTS}/asan:print_stats=0"
export UBSAN_OPTIONS="print_stacktrace=1:halt_on_error=0:log_path=${RESULTS}/ubsan:suppressions=${HERE}/ubsan.supp"

echo "==> Running tests under sanitizers"
: > "${RESULTS}/run.log"
for t in tst_points tst_hangman tst_leaderboard tst_words tst_manager; do
    echo "----- ${t} -----" | tee -a "${RESULTS}/run.log"
    # Sanitizers may set a non-zero exit; capture it without aborting the loop.
    "${BUILD}/${t}" >>"${RESULTS}/run.log" 2>&1 || echo "  (exit $?)" | tee -a "${RESULTS}/run.log"
done

echo "==> Sanitizer reports (asan.* / ubsan.* in ${RESULTS}):"
ls -1 "${RESULTS}" | grep -E '^(asan|ubsan)\.' || echo "  none — no ASan/UBSan errors detected"

echo "==> Done. See ${RESULTS}/run.log and any asan.*/ubsan.* files."
