cmake_minimum_required(VERSION 3.10)

# ---------------------------------------------------------------------------
# Semantic versioning: the version is derived automatically from annotated
# git tags (v<MAJOR>.<MINOR>.<PATCH>).  To cut a release, create a tag:
#     git tag -a v2.2.0 -m "release 2.2.0"
# See cmake/GetVersionFromGit.cmake for details and the tarball fallback.
# ---------------------------------------------------------------------------
include(${CMAKE_CURRENT_LIST_DIR}/cmake/GetVersionFromGit.cmake)
get_version_from_git()

project(sensor_daemon VERSION ${GIT_VERSION_TRIPLET} LANGUAGES CXX)
message(STATUS "sensor_daemon version: ${GIT_SEMVER}")

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Regenerate the version header on every build (cheap, content-guarded) so
# the embedded version tracks git without needing a re-configure.
set(VERSION_HEADER_DIR ${CMAKE_CURRENT_BINARY_DIR}/generated)
set(VERSION_HEADER ${VERSION_HEADER_DIR}/version.h)
add_custom_target(generate_version_header
    COMMAND ${CMAKE_COMMAND}
            -DSRC_DIR=${CMAKE_CURRENT_SOURCE_DIR}
            -DIN_FILE=${CMAKE_CURRENT_SOURCE_DIR}/cmake/version.h.in
            -DOUT_FILE=${VERSION_HEADER}
            -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/GenerateVersionHeader.cmake
    BYPRODUCTS ${VERSION_HEADER}
    COMMENT "Generating version.h from git describe"
    VERBATIM)

add_executable(sensor_daemon src/main.cpp)
add_dependencies(sensor_daemon generate_version_header)
target_include_directories(sensor_daemon PRIVATE ${VERSION_HEADER_DIR})
target_link_libraries(sensor_daemon spdlog opencv_core)
