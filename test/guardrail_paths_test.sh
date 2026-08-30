#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

owners=$(awk '
    NF == 2 && $1 !~ /^#/ && $2 == "@thelarklan" {
        print $1, $2
    }
' "$project_dir/.github/CODEOWNERS")

documented=$(awk '
    /^## The guardrail paths$/ {
        in_section = 1
        next
    }
    in_section && /^```$/ {
        fences++
        if (fences == 2) {
            exit
        }
        next
    }
    in_section && fences == 1 && NF {
        print $1, $2
    }
' "$project_dir/docs/peer-review.md")

[[ -n $owners ]] || {
    printf 'CODEOWNERS contains no human-only guardrail paths\n' >&2
    exit 1
}

[[ $documented == "$owners" ]] || {
    printf 'Documented guardrail paths do not match CODEOWNERS\n' >&2
    diff -u <(printf '%s\n' "$owners") <(printf '%s\n' "$documented") >&2 || true
    exit 1
}

printf 'documented guardrail paths match CODEOWNERS\n'
