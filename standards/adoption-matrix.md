# Review-standard adoption matrix

This matrix tracks declared adoption, not inferred compliance. Enforcement was
audited through the GitHub ruleset API on 2026-08-28 and must be verified again
during each adoption pull request and periodically afterward.

| Repository | Standard | Approval profile | Enforcement | Exceptions | State |
| --- | --- | --- | --- | --- | --- |
| `thelarklan/thelarklan` | `review-standard-v2` | `peer-agents` | Personal; two approvals and trusted check; code-owner review and v2 App reconciliation pending | Protected-approval deployment gap and personal reviewer-identity limitation recorded locally | Adopting via PR #5 (v2 source upgrade) |
| `thelarklan/dev-tools` | `review-standard-v2` | `peer-agents` | Personal; two approvals and trusted check; code-owner review, Jenkins context, and v2 App reconciliation pending | Protected-approval and Jenkins deployment gaps; personal reviewer-identity limitation; `pr-cleanup` extension | Pilot via PR #23 |
| `thelarklan/wsl-tools` | Not adopted | Not declared | User-owned; two approvals, trusted check, and three CI contexts; code-owner review disabled | None recorded | Wave 2 planned |
| `thelarklan/podman-tools` | Not adopted | Not declared | User-owned; two approvals and trusted check; code-owner review disabled; no repository CI required | None recorded | Wave 2 planned |
| `thelarklan/jenkins-controller` | Not adopted | Not declared | User-owned; two approvals and trusted check; code-owner review disabled; no repository CI required | Infrastructure risk requires a repository-specific audit | Wave 3 planned |
| `thelarklan/lol` | Not adopted | Not declared | User-owned; two approvals and trusted check; code-owner review disabled; no repository CI required | Repository scope and verification surface require classification | Wave 4 planned |

Add repositories only through an adoption pull request. Change `State` to
`Adopted` only after the local declaration, managed template, verification,
ownership, and merge protections have been checked at the merged head.

## Incremental rollout

1. Merge and tag the canonical v2 standard, deploy the hardened App permission
   update, then complete the `dev-tools` pilot.
2. Adopt in `wsl-tools` and `podman-tools`, reusing the tooling-oriented policy
   while keeping PowerShell, container, and platform verification local.
3. Audit and adopt in `jenkins-controller` after defining protected deployment,
   credential, and controller-configuration paths plus reliable CI contexts.
4. Classify the `lol` repository's purpose and verification surface before
   selecting an approval profile or copying managed files.

Each wave uses one focused adoption pull request per repository. A repository
does not advance to `Adopted` while a required status context is absent,
code-owner enforcement is disabled, or a recorded exception lacks an owner and
review date.
