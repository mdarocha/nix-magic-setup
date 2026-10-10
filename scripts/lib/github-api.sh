#!/usr/bin/env bash
# GitHub REST API helpers for the current repository, authenticated with $GITHUB_TOKEN.

# GETs $1 under the repository's API URL; extra arguments go to curl, e.g. --data key=value.
github_api() {
    local path=$1
    shift
    curl --fail --silent --show-error --get \
        --header "Authorization: Bearer $GITHUB_TOKEN" \
        --header "Accept: application/vnd.github+json" \
        "$GITHUB_API_URL/repos/$GITHUB_REPOSITORY$path" "$@"
}
