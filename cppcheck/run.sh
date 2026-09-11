#!/usr/bin/env bash

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(realpath "${HERE}/../SketchIt/SketchIt/server")"
RESULTS="${HERE}/results"
mkdir -p "${RESULTS}"

SOURCES=(
    "${SERVER_DIR}/points.cpp"
    "${SERVER_DIR}/hangman.cpp"
    "${SERVER_DIR}/words.cpp"
    "${SERVER_DIR}/leaderboard.cpp"
    "${SERVER_DIR}/player.cpp"
    "${SERVER_DIR}/manager.cpp"
    "${SERVER_DIR}/game.cpp"
    "${SERVER_DIR}/server.cpp"
    "${SERVER_DIR}/main.cpp"
)

COMMON=(
    --enable=all
    --std=c++17
    --library=qt          # bez ovoga: unknownMacro na Q_OBJECT, nalazi padaju 15 -> 6
    -I "${SERVER_DIR}"
    --suppress=missingIncludeSystem   # Qt hederi nisu dati cppcheck-u
    --quiet                           # bez progres-linija u logu
)

echo "==> cppcheck $(cppcheck --version)"

#cppcheck pise sve na stderr (2) pa preusmeravamo na stdout (1)
cppcheck "${COMMON[@]}" \
    --template='{file}:{line}: [{severity}/{id}] {message}' \
    "${SOURCES[@]}" 2>&1 | tee "${RESULTS}/cppcheck.log"

echo "==> Done. See ${RESULTS}/cppcheck.log"
