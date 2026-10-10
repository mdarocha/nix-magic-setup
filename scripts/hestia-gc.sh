#!/usr/bin/env bash
# Runs `hestia gc` on the default branch, the only cache scope that outlives its branch.
# Overlapping gc runs race each other's pack deletes, so only the last running job gcs:
# a job is in_progress before it checks, so two jobs checking at once both skip.
set -euo pipefail
shopt -s inherit_errexit

source "$(dirname "${BASH_SOURCE[0]}")/lib/github-api.sh"

# Prints the URL of every job other than this one running on $default_branch.
other_running_jobs() {
    local run_ids
    run_ids=$(github_api_list /actions/runs workflow_runs \
        --data-urlencode "branch=$default_branch" --data status=in_progress | jq -r .id)

    for run_id in $run_ids; do
        github_api_list "/actions/runs/$run_id/jobs" jobs \
            | jq -r --arg runner "$RUNNER_NAME" 'select(.status == "in_progress" and .runner_name != $runner) | .html_url'
    done
}

if [ -z "${HESTIA_BIN:-}" ]; then
    echo "Skipping hestia gc: hestia wasn't set up"
    exit 0
fi

# The event payload of some triggers (e.g. schedule) may lack the repository.
default_branch=${DEFAULT_BRANCH:-$(github_api "" | jq -r .default_branch)}
if [ "$GITHUB_REF" != "refs/heads/$default_branch" ]; then
    echo "Skipping hestia gc: not on the default branch ($default_branch)"
    exit 0
fi

others=$(other_running_jobs)
if [ -n "$others" ]; then
    echo "Skipping hestia gc: other jobs are still running on $default_branch:"
    echo "$others"
    exit 0
fi

"$HESTIA_BIN" gc
