# GenerateVersionHeader.cmake
#
# Script mode (cmake -P) helper, run at *build* time by the
# `generate_version_header` target so that version.h is refreshed on every
# build without re-running the CMake configure step.
#
# Required -D arguments:
#   SRC_DIR  - repository root (contains .git and VERSION fallback)
#   IN_FILE  - path to version.h.in template
#   OUT_FILE - path of the header to generate
#
# The header is only rewritten when its content actually changes, so
# incremental builds are not invalidated needlessly.

cmake_minimum_required(VERSION 3.10)

set(CMAKE_CURRENT_SOURCE_DIR "${SRC_DIR}")
include("${SRC_DIR}/cmake/GetVersionFromGit.cmake")
get_version_from_git()

configure_file("${IN_FILE}" "${OUT_FILE}.tmp" @ONLY)
execute_process(COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        "${OUT_FILE}.tmp" "${OUT_FILE}")
file(REMOVE "${OUT_FILE}.tmp")
