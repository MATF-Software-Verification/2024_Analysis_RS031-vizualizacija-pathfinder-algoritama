#!/usr/bin/env bash
# What: Runs clang-tidy over the SketchIt server sources.
# Why:  LLVM-based linter that flags bugprone patterns, modernization opportunities
#       and core-guideline violations the compiler doesn't; complements cppcheck
#       (different check engine -> different findings).
# How:  Reuses the unit_tests CMake project to emit a compile_commands.json (so
#       clang-tidy sees the exact Qt include flags), then lints each server .cpp.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(realpath "${HERE}/..")"
SERVER_DIR="$(realpath "${ROOT}/SketchIt/SketchIt/server")"
CDB_BUILD="${HERE}/cdb-build"   # throwaway build dir, only for compile_commands.json
RESULTS="${HERE}/results"
mkdir -p "${RESULTS}"

QT_PREFIX="${QT_PREFIX:-/home/jovan/Qt/6.10.2/gcc_64}"

echo "==> clang-tidy $(clang-tidy --version | head -1)"

echo "==> Generating compile_commands.json via the unit_tests CMake project"
cmake -S "${ROOT}/unit_tests" -B "${CDB_BUILD}" \
      -DCMAKE_PREFIX_PATH="${QT_PREFIX}" \
      -DCMAKE_EXPORT_COMPILE_COMMANDS=ON >/dev/null
# AUTOMOC/AUTORCC generated headers must exist before clang-tidy parses TUs.
cmake --build "${CDB_BUILD}" --target serverlogic_autogen -j"$(nproc)" >/dev/null 2>&1 || true

# Check set: bug-prone + core guidelines + modernize + performance, minus a few
# noisy/irrelevant checks (Qt-style naming, magic numbers, trailing return types).
CHECKS='clang-analyzer-*,bugprone-*,cppcoreguidelines-*,modernize-*,performance-*,misc-*'
CHECKS+=',-modernize-use-trailing-return-type,-cppcoreguidelines-avoid-magic-numbers'
CHECKS+=',-readability-magic-numbers,-modernize-use-auto'

SOURCES=(
    "${SERVER_DIR}/points.cpp"
    "${SERVER_DIR}/hangman.cpp"
    "${SERVER_DIR}/words.cpp"
    "${SERVER_DIR}/leaderboard.cpp"
    "${SERVER_DIR}/player.cpp"
    "${SERVER_DIR}/manager.cpp"
    "${SERVER_DIR}/game.cpp"
)

echo "==> Linting"
: > "${RESULTS}/clang-tidy.log"
for src in "${SOURCES[@]}"; do
    echo "----- ${src##*/} -----" | tee -a "${RESULTS}/clang-tidy.log"
    # -p points clang-tidy at the compile DB; header-filter restricts diagnostics
    # to the project's own headers (not Qt's).
    clang-tidy -p "${CDB_BUILD}" \
        --checks="${CHECKS}" \
        --header-filter="${SERVER_DIR}/.*" \
        "${src}" 2>/dev/null | tee -a "${RESULTS}/clang-tidy.log" || true
done

echo "==> Done. See ${RESULTS}/clang-tidy.log"
