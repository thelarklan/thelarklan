# Peer review between agent accounts

This repository is **being set up** so that AI agent accounts open pull
requests, review each other's work, and merge automatically once approvals
land, with a human in the loop only where it matters.

That is the target, not a description of today. Parts of it are live and
parts are not — most importantly the merge gate, without which "merge
automatically once approvals land" means "merge whenever, approvals
optional". Read [*Current state*](#current-state) before relying on any
behaviour described here in the present tense.

This document describes how that arrangement works, what each piece is
actually doing, and where the sharp edges are.
[`review-checking.md`](review-checking.md) is its companion: this document
covers who is asked to review, that one covers how an agent finds the
request.

## The participants

| Account           | Intended access | Part it plays                                   |
| ----------------- | --------------- | ----------------------------------------------- |
| `@thelarklan`     | Admin           | Human owner. Sole owner of the guardrail paths. |
| `@larkbot-codex`  | Write           | Agent. Opens PRs, reviews the others'.          |
| `@larkbot-gemini` | Write           | Agent. Opens PRs, reviews the others'.          |
| `@larkbot-claude` | Write           | Agent. Opens PRs, reviews the others'.          |

The Access column is the **intended** configuration, not a claim about what
is currently granted; *Current state* below records what was actually read
from the API, and it is the section to trust. The distinction matters
because an entry for an account that does not yet hold write access is
discarded in silence, so intent and reality are indistinguishable from the
outside.

The agents hold **Write**, deliberately not Admin. Admin would let an agent
edit the ruleset described below and remove its own constraints.

Write access is required even though the agents contribute from **forks**
and never push a branch to this repository. The two are unrelated: pushing
to a fork needs no access here, but a CODEOWNERS entry naming an account
without write access is discarded silently. Fork-based contribution and
code ownership are separate requirements, and it is easy to conclude that
the first makes the second unnecessary.

## How reviewers get chosen

`.github/CODEOWNERS` lists all four accounts as owners of everything:

```
*                       @larkbot-codex @larkbot-gemini @larkbot-claude @thelarklan
```

The mechanism that turns this into *peer* review is a GitHub rule that is
easy to miss: **GitHub never requests a review from the author of a pull
request.** Whoever opens the PR drops out of the owner list automatically,
and review is requested from the remaining owners. No routing logic, no
assignment step — the author excludes themselves by writing the PR.

Two conditions have to hold or this silently does nothing:

- The CODEOWNERS that applies to a pull request is the one on **that PR's
  base branch**, not the repository default branch. Branches may carry
  different ownership files, and that is supported. A PR based on a branch
  with no CODEOWNERS gets no code-owner review request — so a
  non-default-base PR routing "wrongly" is usually correct behaviour, not a
  fault to chase. For a fork PR the file still comes from the base
  repository's base branch; the fork's copy is never consulted.
- An owner must have **write access**. An entry naming an account without
  it is ignored with no error and no warning — a pending collaborator
  invitation looks identical to a working setup until you notice reviews
  are never requested.

A third condition has bitten this repository already: **the account has to
exist.** An entry naming a login that no longer resolves is discarded on
the same silent path as one lacking access.

## The guardrail paths

Seven path rules override the global rule (last match wins) and are owned by
the human alone. The base branch's `.github/CODEOWNERS` is the authoritative
local list:

```
/.github/workflows/     @thelarklan
/.github/CODEOWNERS     @thelarklan
/standards/             @thelarklan
/templates/             @thelarklan
/scripts/               @thelarklan
/test/                  @thelarklan
/docs/review-policy.md  @thelarklan
```

These paths define the standard, its distribution and tests, CI, ownership,
and the repository's adoption and exception policy. An agent that could change
them without owner approval could weaken the review contract or its enforcement
in a single pull request. Keeping them human-owned makes that move stop for a
person. The trusted App's private protected-path map must match these base-branch
rules; disagreement is a fail-closed audit finding.

## The merge gate

A branch ruleset named `main protection` should target the default branch:

- Require a pull request before merging
  - 2 required approvals
  - Dismiss stale approvals when new commits are pushed
  - Require review from Code Owners
  - Require approval of the most recent reviewable push
- Restrict deletions
- Block force pushes
- Require the head-pinned `bot-review-quorum` check from the trusted App
- Bypass: none

Add every repository CI context when it exists. The trusted check is separate:
native review slots in a personal repository accept any write collaborator,
while the App verifies that the rotating two configured agents supplied the
exact-head approvals.

"Dismiss stale approvals" and "require approval of the most recent
reviewable push" exist together for a reason: without them, an agent could
collect approvals on a harmless diff and then push something else before
the merge fires.

Combined with auto-merge, the normal path for an agent PR is: open it, collect
both other agent approvals, let the App arm auto-merge, and let GitHub merge
with no human involved. A guardrail PR adds human content approval and then
follows the same GitHub merge path.

## Current state

The 2026-08-28 audit found the two-approval, stale-review, latest-push,
conversation, current-base, squash-only, and trusted-check rules active with no
bypass. Code-owner review remains disabled. Repository auto-merge is enabled,
but v2 App reconciliation and its pull-request write permission are not yet
deployed. Leave individual PR auto-merge unarmed until those gaps are closed
and both a routine and protected acceptance PR pass.

## Known sharp edges

**A guardrail PR opened by the human has no eligible approver.** On
any guardrail path listed in the base branch's `.github/CODEOWNERS`,
`@thelarklan` is the only code owner — and is excluded as the author. "Require
review from Code Owners" cannot be satisfied by any allowed route. This is a
consequence of author-exclusion meeting a single-owner path, not a reason to
bypass it. A guardrail PR must be agent-authored so the human can approve it.

**Quorum depends on who opened the PR.** With four owners, an agent-opened
PR leaves three eligible approvers for two required approvals, which has
slack in it. A PR the human opens leaves the three agents, and needs two of
them awake. That is the tighter case, and the one to watch: if bypassing
starts happening routinely on human-opened PRs, the required count is too
high for a repository this size and 1 is the honest number.

**A personal repository cannot bind approval slots to agent identities.** The
trusted App supplies that missing identity gate. Its one-minute poll is not an
atomic revocation mechanism, so the owner does not approve routine bot PRs and
outside accounts do not receive write access without protected review.

**Write access without the ruleset is worse than no setup.** Collaborators
should be added only once the ruleset is active. In the window between the
two, an agent can push straight to the default branch and skip review
entirely. This repository was in that window for part of 2026-08-26 —
three agents on Write against an unprotected `main` — and closed it by
creating the ruleset rather than by removing access. Worth recording as the
order to follow next time: ruleset first, collaborators second.

**A silently ignored owner and a quiet week look identical.** Whether the
cause is a missing account, missing write access, or no CODEOWNERS on the
pull request's base branch, the symptom is the same — no review requests arrive, and
nothing reports an error. Nobody notices an absence. This is the specific
failure the checking protocol is built to survive.
