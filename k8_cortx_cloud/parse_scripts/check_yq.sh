#!/usr/bin/env bash

# This script verifies that the yq command line tool is available and
# meets the minimum required version. yq is required to use the
# deployment scripts and is expected to be in the user's PATH.

set -euo pipefail

error() {
    echo >&2 "$@"
}

die() {
    echo >&2 "$@"
    exit 1
}

check_yq() {
    local -r req_major=4
    local -r req_minor=25
    local -r req_patch=1
    local -r minimum_version="${req_major}.${req_minor}.${req_patch}"
    local -r install_msg="The required version is ${minimum_version} or higher. See https://github.com/mikefarah/yq#install for installation instructions."

    if ! command -v yq &>/dev/null; then
        die "Missing required program 'yq'. ${install_msg}"
    fi

    # Require yq v4.25.1 or later. There are a number of bug fixes and
    # features available in this version that we depend on.
    if ! yq_version="$(yq --version)"; then
        error "${yq_version}"
        die "yq is installed but the version could not be determined. ${install_msg}"
    fi

    local -r incompatible="yq is installed but is not compatible. ${install_msg}"

    # There is another yq utility, make sure this is the desired one.
    # Older versions also lack the Github project name.
    if [[ ${yq_version} != *"mikefarah/yq"* ]]; then
        error "${yq_version}"
        die "${incompatible}"
    fi

    # Extract the version number from the entire version output
    yq_version_num=${yq_version##*version }

    # Split the version number into its individual components
    IFS=. read -r yq_major yq_minor yq_patch <<< "${yq_version_num}"
    # Technically the patch version can be a string like "0-alpha1", so strip any suffixes to be safe.
    yq_patch="${yq_patch%-*}"

    # Assume any new major version is incompatible.
    if (( yq_major != req_major )) || (( yq_minor < req_minor )) || (( yq_minor == 25 && yq_patch < req_patch)); then
        error "${yq_version}"
        die "${incompatible}"
    fi
}

check_yq
