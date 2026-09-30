# This guard only affects our named development branches. Production is unchanged.
execute_process(
    COMMAND git -C "${CMAKE_CURRENT_LIST_DIR}" symbolic-ref --quiet --short HEAD
    OUTPUT_VARIABLE _fw_dev_branch OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
if(NOT _fw_dev_branch MATCHES "^dev/firmware-(round|pro)$")
    return()
endif()

if(_fw_dev_branch STREQUAL "dev/firmware-round")
    set(_fw_dev_chip "esp32s3")
else()
    set(_fw_dev_chip "esp32p4")
endif()
if(DEFINED IDF_TARGET AND NOT IDF_TARGET STREQUAL _fw_dev_chip)
    message(FATAL_ERROR "${_fw_dev_branch} only builds ${_fw_dev_chip}; wrong hardware target")
endif()
set(IDF_TARGET "${_fw_dev_chip}" CACHE STRING "Development hardware target" FORCE)

# Fail early if an old command/cache attempts to borrow a customer's release number.
if(DEFINED PROJECT_VER AND NOT PROJECT_VER MATCHES "^0\\.0\\.0-dev\\.[0-9a-f]+(-dirty)?$")
    message(FATAL_ERROR
        "Development firmware must not use PROJECT_VER=${PROJECT_VER}. "
        "Omit PROJECT_VER and use a dedicated development build directory.")
endif()
execute_process(
    COMMAND git -C "${CMAKE_CURRENT_LIST_DIR}" rev-parse --short=10 HEAD
    RESULT_VARIABLE _fw_dev_git_result
    OUTPUT_VARIABLE _fw_dev_commit OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT _fw_dev_git_result EQUAL 0)
    message(FATAL_ERROR "Cannot identify development source commit")
endif()
execute_process(
    COMMAND git -C "${CMAKE_CURRENT_LIST_DIR}" status --porcelain --untracked-files=normal
    RESULT_VARIABLE _fw_dev_status_result
    OUTPUT_VARIABLE _fw_dev_dirty OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT _fw_dev_status_result EQUAL 0)
    message(FATAL_ERROR "Cannot determine whether development source is clean")
endif()
set(_fw_dev_version "0.0.0-dev.${_fw_dev_commit}")
if(NOT _fw_dev_dirty STREQUAL "")
    string(APPEND _fw_dev_version "-dirty")
endif()
set(PROJECT_VER "${_fw_dev_version}" CACHE STRING "Development image identity" FORCE)
message(STATUS "Development firmware: ${_fw_dev_branch} / ${IDF_TARGET} / ${PROJECT_VER}")
