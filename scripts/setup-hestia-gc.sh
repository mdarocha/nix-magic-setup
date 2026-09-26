#!/usr/bin/env bash
# Decides whether this job runs hestia gc. Concurrent gc runs corrupt the cache,
# so gc runs only in the single job in the `hestia-gc` concurrency group, and
# only on the default branch, whose cache scope is the one that keeps growing.
set -euo pipefail

readonly GC_GROUP=hestia-gc

yq=(yq)
# Only mikefarah's yq; the Python yq wrapper takes a different syntax.
if ! type -P yq > /dev/null || ! yq --version | grep -q mikefarah; then
    yq=(nix --extra-experimental-features 'nix-command flakes' run nixpkgs#yq-go --)
fi

# Prints "<workflow path>:<job id>" for each job in $GC_GROUP. A workflow-level
# group covers all of that workflow's jobs, as it doesn't serialize jobs within a run.
gc_jobs() {
    shopt -s nullglob
    local workflows=(.github/workflows/*.yml .github/workflows/*.yaml)
    if [ "${#workflows[@]}" -eq 0 ]; then
        return 0
    fi

    "${yq[@]}" -o=json -I=0 '{"file": filename, "workflow": .}' "${workflows[@]}" \
        | jq -r --arg group "$GC_GROUP" '
            def group: if type == "object" then .group else . end;
            .file as $file
            | ((.workflow.concurrency | group) == $group) as $whole_workflow
            | .workflow.jobs // {} | to_entries[]
            | select($whole_workflow or (.value.concurrency | group) == $group)
            | "\($file):\(.key)"
        '
}

owns_gc() {
    if [ "$GITHUB_REF" != "refs/heads/$DEFAULT_BRANCH" ]; then
        return 1
    fi

    if [ "${#owners[@]}" -eq 0 ]; then
        echo "::warning::No job uses concurrency group '$GC_GROUP', so hestia gc never runs. Add it to the job that should run gc."
        return 1
    fi

    # GITHUB_WORKFLOW_REF is "<owner>/<repo>/<workflow path>@<ref>".
    local workflow="${GITHUB_WORKFLOW_REF#*/*/}"
    [ "${owners[0]}" = "${workflow%@*}:$GITHUB_JOB" ]
}

cd "$GITHUB_WORKSPACE"

owners=()
jobs=$(gc_jobs)
if [ -n "$jobs" ]; then
    mapfile -t owners <<< "$jobs"
fi

if [ "${#owners[@]}" -gt 1 ]; then
    echo "::error::hestia gc needs exactly one job in concurrency group '$GC_GROUP', found: ${owners[*]}"
    exit 1
fi

if owns_gc; then
    echo "This job owns hestia gc; it runs after the job's remaining steps"
    echo "should-run=true" >> "$GITHUB_OUTPUT"
else
    echo "should-run=false" >> "$GITHUB_OUTPUT"
fi
