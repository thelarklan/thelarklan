#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s [--check] TARGET_REPOSITORY\n' "${0##*/}" >&2
    exit 2
}

mode=sync
if [[ ${1:-} == --check ]]; then
    mode=check
    shift
fi
[[ $# -eq 1 ]] || usage

target=$1
source_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source_template=$source_root/templates/pull_request_template.md
target_template=$target/.github/pull_request_template.md
target_policy=$target/docs/review-policy.md
target_owners=$target/.github/CODEOWNERS
human_owner=

[[ -d $target ]] || { printf 'Target repository does not exist: %s\n' "$target" >&2; exit 1; }
[[ -f $source_template ]] || { printf 'Canonical template is missing: %s\n' "$source_template" >&2; exit 1; }
[[ -f $target_policy ]] || { printf 'Consumer policy is missing: %s\n' "$target_policy" >&2; exit 1; }
[[ -f $target_owners ]] || { printf 'Consumer CODEOWNERS is missing: %s\n' "$target_owners" >&2; exit 1; }

grep -Eq '^Standard: review-standard-v2[[:space:]]*$' "$target_policy" || {
    printf 'Consumer policy does not adopt review-standard-v2: %s\n' "$target_policy" >&2
    exit 1
}
grep -Eq '^Approval profile: (peer-agents|human)[[:space:]]*$' "$target_policy" || {
    printf 'Consumer policy has no valid approval profile: %s\n' "$target_policy" >&2
    exit 1
}
human_owner=$(sed -nE 's/^Human owner: (@[A-Za-z0-9-]+)[[:space:]]*$/\1/p' "$target_policy")
if [[ -z $human_owner || $human_owner == *$'\n'* ]]; then
    printf 'Consumer policy has no human owner: %s\n' "$target_policy" >&2
    exit 1
fi
if ! awk -v owner="$human_owner" '
    /^[[:space:]]*(#|$)/ { next }
    {
        for (field = 2; field <= NF; field++) {
            if ($field == owner) {
                found = 1
            }
        }
    }
    END { exit(found ? 0 : 1) }
' "$target_owners"; then
    printf 'Consumer CODEOWNERS has no effective rule naming human owner %s: %s\n' \
        "$human_owner" "$target_owners" >&2
    exit 1
fi

if [[ $mode == check ]]; then
    if [[ ! -f $target_template ]] || ! cmp -s -- "$source_template" "$target_template"; then
        printf 'Managed pull-request template is out of date: %s\n' "$target_template" >&2
        exit 1
    fi
    printf 'Review-standard adoption conforms: %s\n' "$target"
    exit 0
fi

mkdir -p -- "${target_template%/*}"
cp -- "$source_template" "$target_template"
printf 'Synchronized review-standard-v2 template: %s\n' "$target_template"
