#!/usr/bin/env bash
# GitHub REST API helpers for the current repository, authenticated with $GITHUB_TOKEN.

readonly GITHUB_API_PAGE_SIZE=100

# GETs $1 under the repository's API URL; extra arguments go to curl, e.g. --data key=value.
github_api() {
    local path=$1
    shift
    curl --fail --silent --show-error --get \
        --header "Authorization: Bearer $GITHUB_TOKEN" \
        --header "Accept: application/vnd.github+json" \
        "$GITHUB_API_URL/repos/$GITHUB_REPOSITORY$path" "$@"
}

# Prints each item of the response's $2 array, across all pages.
github_api_list() {
    local path=$1 field=$2 page=1 body
    shift 2

    while :; do
        body=$(github_api "$path" --data "per_page=$GITHUB_API_PAGE_SIZE" --data "page=$page" "$@")
        jq -c --arg field "$field" '.[$field][]' <<< "$body"

        if [ "$(jq --arg field "$field" '.[$field] | length' <<< "$body")" -lt "$GITHUB_API_PAGE_SIZE" ]; then
            return
        fi
        page=$((page + 1))
    done
}
