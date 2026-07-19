# GetVersionFromGit.cmake
#
# Computes the project's semantic version from git at configure time.
#
# The single source of truth for released versions is an annotated git tag
# of the form  v<MAJOR>.<MINOR>.<PATCH>  (e.g. v2.1.0).  Future releases
# are made by tagging:   git tag -a v2.2.0 -m "release 2.2.0"
#
# Output variables (set in the caller's scope):
#   GIT_SEMVER          Full semantic version string.
#                       - exactly on a tag:      2.1.0
#                       - N commits past a tag:  2.1.0+15.g1a2b3c4  (metadata)
#                       - dirty work tree:       ...-dirty suffix appended
#   GIT_VERSION_MAJOR   e.g. 2
#   GIT_VERSION_MINOR   e.g. 1
#   GIT_VERSION_PATCH   e.g. 0
#   GIT_VERSION_TRIPLET MAJOR.MINOR.PATCH only (usable as project VERSION)
#   GIT_DESCRIBE        Raw `git describe` output (or fallback marker)
#
# Fallback: when building from a source archive without git metadata, the
# version is read from the VERSION file in the repository root instead.

function(get_version_from_git)
    find_package(Git QUIET)

    set(_describe "")
    if(GIT_FOUND AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/.git")
        execute_process(
            COMMAND ${GIT_EXECUTABLE} describe --tags --long --dirty
                    --match "v[0-9]*"
            WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
            OUTPUT_VARIABLE _describe
            RESULT_VARIABLE _result
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET)
        if(NOT _result EQUAL 0)
            set(_describe "")
        endif()
    endif()

    if(_describe MATCHES
       "^v([0-9]+)\\.([0-9]+)\\.([0-9]+)-([0-9]+)-g([0-9a-f]+)(-dirty)?$")
        set(_major "${CMAKE_MATCH_1}")
        set(_minor "${CMAKE_MATCH_2}")
        set(_patch "${CMAKE_MATCH_3}")
        set(_ncommits "${CMAKE_MATCH_4}")
        set(_sha "${CMAKE_MATCH_5}")
        set(_dirty "${CMAKE_MATCH_6}")

        set(_semver "${_major}.${_minor}.${_patch}")
        if(_ncommits GREATER 0)
            # Not an exact release: append build metadata (SemVer 2.0.0).
            string(APPEND _semver "+${_ncommits}.g${_sha}")
        endif()
        if(_dirty)
            string(APPEND _semver "-dirty")
        endif()
    else()
        # No usable git metadata (e.g. source tarball): use VERSION file.
        file(READ "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" _fallback)
        string(STRIP "${_fallback}" _fallback)
        if(NOT _fallback MATCHES "^([0-9]+)\\.([0-9]+)\\.([0-9]+)$")
            message(FATAL_ERROR
                "VERSION file must contain MAJOR.MINOR.PATCH, "
                "got: '${_fallback}'")
        endif()
        set(_major "${CMAKE_MATCH_1}")
        set(_minor "${CMAKE_MATCH_2}")
        set(_patch "${CMAKE_MATCH_3}")
        set(_semver "${_fallback}")
        set(_describe "VERSION-file:${_fallback}")
        message(STATUS
            "sensor_daemon: no git tag info, using VERSION file fallback")
    endif()

    set(GIT_SEMVER "${_semver}" PARENT_SCOPE)
    set(GIT_VERSION_MAJOR "${_major}" PARENT_SCOPE)
    set(GIT_VERSION_MINOR "${_minor}" PARENT_SCOPE)
    set(GIT_VERSION_PATCH "${_patch}" PARENT_SCOPE)
    set(GIT_VERSION_TRIPLET "${_major}.${_minor}.${_patch}" PARENT_SCOPE)
    set(GIT_DESCRIBE "${_describe}" PARENT_SCOPE)
endfunction()
