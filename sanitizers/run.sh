#!/usr/bin/env bash

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="${HERE}/build"
RESULTS="${HERE}/results"
mkdir -p "${RESULTS}"

QT_PREFIX="${QT_PREFIX:-/home/jovan/Qt/6.10.2/gcc_64}"

SAN_FLAGS="-fsanitize=address,undefined,unsigned-integer-overflow -fsanitize-recover=unsigned-integer-overflow -fno-omit-frame-pointer -g -O1"

# gcc odbija unsigned-integer-overflow, pa mora clang++
CXX_COMPILER="${CXX_COMPILER:-clang++}"

echo "==> Configuring with ASan + UBSan (clang, coverage off)"
cmake -S "${HERE}/../tests" -B "${BUILD}" \
    -DCMAKE_PREFIX_PATH="${QT_PREFIX}" \
    -DCMAKE_CXX_COMPILER="${CXX_COMPILER}" \
    -DENABLE_COVERAGE=OFF \
    -DCMAKE_CXX_FLAGS="${SAN_FLAGS}" >/dev/null

echo "==> Building"
cmake --build "${BUILD}" -j"$(nproc)" >/dev/null

export QT_QPA_PLATFORM=offscreen

export ASAN_OPTIONS="detect_leaks=1:log_path=${RESULTS}/report"
export UBSAN_OPTIONS="print_stacktrace=1:log_path=${RESULTS}/report:suppressions=${HERE}/ubsan.supp"

echo "==> Running tests under sanitizers"
#ocisti prethodne prvo
rm -f "${RESULTS}"/report.*
: > "${RESULTS}/run.log" #isprazni rezultate
for t in tst_points tst_hangman tst_leaderboard tst_words tst_manager; do
    echo "----- ${t} -----" | tee -a "${RESULTS}/run.log"
    "${BUILD}/${t}" >>"${RESULTS}/run.log" 2>&1 || echo "  (exit $?)" | tee -a "${RESULTS}/run.log"
done

echo "==> Sanitizer reports (report.* in ${RESULTS}):"
ls -1 "${RESULTS}" | grep -E '^report\.' || echo "  none - no ASan/UBSan errors detected"

echo "==> Done. See ${RESULTS}/run.log and any report.* files."
