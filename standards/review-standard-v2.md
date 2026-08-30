# Review standard v2

Status: normative
Identifier: `review-standard-v2`

This is the common review contract for repositories under `thelarklan`. A
consumer repository implements it through the adoption contract and documents
only repository-specific verification, ownership, protected paths, extensions,
and exceptions.

## Roles and approval profiles

Every pull request has a submitter and one or more independent reviewers. The
submitter never approves their own pull request. Each repository declares one
routine-change approval profile:

- `peer-agents`: exactly three configured agent accounts form the review
  cohort. A bot-authored pull request requires exact-current-head approvals
  from both other agents. A human-owner-authored pull request requires
  exact-current-head approvals from any two cohort agents.
- `human`: at least one eligible non-author human code owner approves the exact
  current head.

Only native reviews by configured principals count. The trusted App supplies
identity and revision evidence; its check never substitutes for a review.
Authors outside the configured human owner and agent cohort are ineligible for
automatic merge until an eligible agent reauthors the change.

Protected and explicitly high-risk changes require approval from the human
owner in addition to the routine profile. At minimum these include ownership,
review policy and enforcement, CI and local verification enforcement, trusted
review or merge automation, credentials, and deployment controls. The consumer
repository's base-branch `CODEOWNERS` is the authoritative local protected-path
list and may extend this minimum. The trusted App's private map must cover the
same protected rules and may be stricter, never weaker.

The sole human owner must not author a protected change because they cannot
approve their own pull request. An agent must author it for human review, or a
second eligible human owner must be added. Agents never use an administrator
bypass.

## Pull-request lifecycle

1. Start from the current upstream default branch and use a focused feature
   branch. One pull request introduces one independently useful change.
2. Open as a draft with the canonical pull-request template and classify the
   change as routine or protected from the base branch's ownership rules.
3. Keep behavior, user guidance, tests, and CI contracts aligned.
4. Run every repository-required tree and pull-request-diff check at the exact
   head offered for review. Record the base, head, environment, commands, and
   observed results.
5. Mark ready only when available required checks pass and manual verification
   is complete. A missing required environment keeps the pull request in draft
   unless the human owner explicitly accepts the recorded limitation.
6. Any new commit or history rewrite invalidates earlier evidence and review.
   Rerun checks, update the recorded head, and obtain reviews of that head.
7. Arm squash auto-merge through the trusted App. GitHub, not a review agent or
   repository helper, performs the merge after every repository rule passes.

## Review method and findings

Reviewers make three distinct passes:

1. **Intent and scope:** the change solves the stated problem, remains focused,
   and identifies deferred behavior.
2. **Correctness and risk:** behavior, failure and recovery paths, security,
   compatibility, destructive operations, and negative tests are sound.
3. **Standards and maintenance:** repository conventions, documentation,
   portability, operability, and test coverage remain aligned.

Findings use these severities:

- `blocker`: unsafe or incorrect; must be fixed before approval.
- `warning`: material risk or maintainability defect; must be fixed or
  explicitly accepted by the human owner before approval.
- `suggestion`: worthwhile improvement that is not required for this change.
- `nit`: optional local polish.

Each blocking finding states its consequence and evidence. The reviewer who
opened a blocking thread resolves it or confirms the response; authors do not
self-resolve blocking review findings merely because code changed.

## Personal-repository merge gate

The protected default branch has an active ruleset with no bypass actors that:

- requires pull requests, two native approvals, stale-approval dismissal, and
  approval of the latest reviewable push;
- requires code-owner review so protected paths stop for the human owner;
- requires resolved conversations and a branch current with its base;
- requires every mandatory CI context and the head-pinned trusted App check;
- permits only squash merge; and
- blocks force pushes and branch deletion.

The trusted App is the agent-identity boundary unavailable in a personal
repository's native rules. It stores stable account IDs in private deployment
configuration, never trusts identities or policy supplied by pull-request
code, never checks out or executes pull-request code, and fails closed on API,
identity, state, pagination, or revision ambiguity.

Immediately before publishing success and arming auto-merge, the App re-reads
the open, non-draft pull request, complete changed-file list, exact head,
default base, author, and complete latest decisive review state. It classifies
paths against a private per-repository map of exact paths and directory
prefixes. It requires the rotating two-agent quorum, plus the configured human
owner's exact-head approval for a protected change. If a human-owner approval
exists on a routine bot-authored change, the App publishes failure and disables
auto-merge until that approval is dismissed; it does not merely omit the review
from the quorum count. The native code-owner rule supplies an additional
protected-path gate. The App then re-reads the head again.

The App may have metadata read, pull-request read/write, and checks read/write
permissions solely to inspect files and reviews, publish or revoke its check,
and enable or disable auto-merge. It must not have contents write,
administration, workflow, secrets, deployment, or ruleset-bypass permission and
must never call a direct-merge endpoint.

The App re-evaluates relevant pull-request and review state through authenticated
events or a polling interval of at most one minute, with periodic reconciliation
as the fallback. A missing or changed quorum replaces success with failure and
disables auto-merge. A new commit naturally has no trusted success for its new
head. GitHub remains the only component that merges.

The stable account IDs and protected-path map live in mode-restricted private
deployment configuration. Every installed repository has an explicit non-empty
entry and an auto-merge rollout switch. A disabled repository may receive the
trusted check but no auto-merge mutation. Missing configuration, unsafe
patterns, file-list failure, or drift between the private map and protected
base-branch policy fails closed and is an audit finding. Pull-request-controlled
files cannot weaken the gate that applies to that pull request.

A personal repository cannot synchronously restrict native approval slots to
specific users. Event delivery and reconciliation therefore leave a bounded
revocation interval that does not exist with organization team rules. During
that interval the native two-approval, stale-review, latest-push, CI, and
code-owner controls remain active. The human owner must not approve a routine
bot-authored pull request, and no write collaborator outside the owner and the
three-agent cohort may be added without treating that access change as a
protected policy change. This limitation must be recorded in the local policy,
not described as fully synchronous or perfectly fail-closed.

## Local adoption and exceptions

The consumer adoption file is authoritative for local commands, protected
paths, and extensions; this document remains authoritative for common intent.
Exceptions identify the exact rule, justification, compensating control,
owner, and review date. Silence is not an exception.

Changes to normative behavior create a new standard version. Editorial fixes
may update this document without changing its identifier.
