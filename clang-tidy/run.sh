#!/usr/bin/env bash

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(realpath "${HERE}/..")"
SERVER_DIR="$(realpath "${ROOT}/SketchIt/SketchIt/server")"
CDB_BUILD="${HERE}/cdb-build"       
RESULTS="${HERE}/results"
mkdir -p "${RESULTS}"

QT_PREFIX="${QT_PREFIX:-/home/jovan/Qt/6.10.2/gcc_64}"

echo "==> clang-tidy $(clang-tidy --version | head -1)"

echo "==> Generating compile_commands.json via the tests CMake project"
cmake -S "${ROOT}/tests" -B "${CDB_BUILD}" \
      -DCMAKE_PREFIX_PATH="${QT_PREFIX}" \
      -DCMAKE_EXPORT_COMPILE_COMMANDS=ON >/dev/null # potrebno za Qt headere
#potrebno za moc fajlove
cmake --build "${CDB_BUILD}" --target serverlogic_autogen -j"$(nproc)" >/dev/null 2>&1 || true

CHECKS='clang-analyzer-*,bugprone-*,cppcoreguidelines-*,modernize-*,performance-*,misc-*'
CHECKS+=',-modernize-use-trailing-return-type,-cppcoreguidelines-avoid-magic-numbers'
CHECKS+=',-modernize-use-auto'

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
    #src##*/ brise najduze poklpanje */ s pocetka, samo hvata ime fajla
    echo "----- ${src##*/} -----" | tee -a "${RESULTS}/clang-tidy.log"
 
    clang-tidy -p "${CDB_BUILD}" \
        --checks="${CHECKS}" \
        --header-filter="${SERVER_DIR}/.*" \
        "${src}" | tee -a "${RESULTS}/clang-tidy.log" || true #true neophodno jer clang-tidy vraca ne nula izlaz
done

echo "==> Done. See ${RESULTS}/clang-tidy.log"
