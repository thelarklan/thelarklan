#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

consumer=$test_dir/consumer
mkdir -p -- "$consumer/.github" "$consumer/docs"
cp -- "$project_dir/docs/review-policy.md" "$consumer/docs/review-policy.md"
cp -- "$project_dir/.github/CODEOWNERS" "$consumer/.github/CODEOWNERS"

bash "$project_dir/scripts/sync-review-standard.sh" "$consumer"
cmp -- "$project_dir/templates/pull_request_template.md" "$consumer/.github/pull_request_template.md"
bash "$project_dir/scripts/sync-review-standard.sh" --check "$consumer"

printf '\n<!-- drift -->\n' >>"$consumer/.github/pull_request_template.md"
if bash "$project_dir/scripts/sync-review-standard.sh" --check "$consumer" 2>"$test_dir/drift-error"; then
    fail "check mode accepted a modified managed template"
fi
grep -Fq 'template is out of date' "$test_dir/drift-error"
bash "$project_dir/scripts/sync-review-standard.sh" "$consumer" >/dev/null

sed -i 's/Approval profile: peer-agents/Approval profile: invalid/' "$consumer/docs/review-policy.md"
if bash "$project_dir/scripts/sync-review-standard.sh" "$consumer" 2>"$test_dir/profile-error"; then
    fail "sync accepted an invalid approval profile"
fi
grep -Fq 'no valid approval profile' "$test_dir/profile-error"
cp -- "$project_dir/docs/review-policy.md" "$consumer/docs/review-policy.md"

sed -i '/^Standard: /d' "$consumer/docs/review-policy.md"
if bash "$project_dir/scripts/sync-review-standard.sh" --check "$consumer" 2>"$test_dir/standard-error"; then
    fail "check mode accepted a missing standard declaration"
fi
grep -Fq 'does not adopt review-standard-v2' "$test_dir/standard-error"
cp -- "$project_dir/docs/review-policy.md" "$consumer/docs/review-policy.md"

sed -i 's/^Human owner: @thelarklan$/Human owner: @thelarklan  /' "$consumer/docs/review-policy.md"
bash "$project_dir/scripts/sync-review-standard.sh" --check "$consumer" >/dev/null ||
    fail "check mode rejected trailing policy whitespace"
cp -- "$project_dir/docs/review-policy.md" "$consumer/docs/review-policy.md"

sed -i 's/$/\r/' "$consumer/docs/review-policy.md"
bash "$project_dir/scripts/sync-review-standard.sh" --check "$consumer" >/dev/null ||
    fail "check mode rejected a CRLF policy"
cp -- "$project_dir/docs/review-policy.md" "$consumer/docs/review-policy.md"

: >"$consumer/.github/CODEOWNERS"
if bash "$project_dir/scripts/sync-review-standard.sh" --check "$consumer" 2>"$test_dir/owners-content-error"; then
    fail "check mode accepted empty CODEOWNERS"
fi
grep -Fq 'no effective rule naming human owner' "$test_dir/owners-content-error"
cp -- "$project_dir/.github/CODEOWNERS" "$consumer/.github/CODEOWNERS"

mv -- "$consumer/docs/review-policy.md" "$consumer/docs/review-policy.saved"
if bash "$project_dir/scripts/sync-review-standard.sh" --check "$consumer" 2>"$test_dir/policy-file-error"; then
    fail "check mode accepted a missing consumer policy"
fi
grep -Fq 'Consumer policy is missing' "$test_dir/policy-file-error"
mv -- "$consumer/docs/review-policy.saved" "$consumer/docs/review-policy.md"

mv -- "$consumer/.github/CODEOWNERS" "$consumer/.github/CODEOWNERS.saved"
if bash "$project_dir/scripts/sync-review-standard.sh" --check "$consumer" 2>"$test_dir/owners-file-error"; then
    fail "check mode accepted missing CODEOWNERS"
fi
grep -Fq 'Consumer CODEOWNERS is missing' "$test_dir/owners-file-error"
mv -- "$consumer/.github/CODEOWNERS.saved" "$consumer/.github/CODEOWNERS"

mv -- "$consumer/.github/pull_request_template.md" "$consumer/.github/pull_request_template.saved"
if bash "$project_dir/scripts/sync-review-standard.sh" --check "$consumer" 2>"$test_dir/template-file-error"; then
    fail "check mode accepted a missing managed template"
fi
grep -Fq 'template is out of date' "$test_dir/template-file-error"
mv -- "$consumer/.github/pull_request_template.saved" "$consumer/.github/pull_request_template.md"

printf 'review standard synchronization tests passed\n'
