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

Two paths override the global rule (last match wins) and are owned by the
human alone:

```
/.github/workflows/     @thelarklan
/.github/CODEOWNERS     @thelarklan
```

These are the paths that control the merge gate itself. CI defines what
"passing" means; CODEOWNERS defines who gets to approve. An agent that
could change either could widen its own permissions in a single PR — and
with auto-merge enabled, do it without anyone watching. Keeping them
human-owned means that particular move always stops for a person.

## The merge gate

A branch ruleset named `main protection` should target the default branch:

- Require a pull request before merging
  - 2 required approvals
  - Dismiss stale approvals when new commits are pushed
  - Require review from Code Owners
  - Require approval of the most recent reviewable push
- Restrict deletions
- Block force pushes
- Bypass: Repository admin

Status checks are **not** required, because no CI exists yet. When CI is
added, that rule should be turned on — and note that adding it means
touching `/.github/workflows/`, a guardrail path.

"Dismiss stale approvals" and "require approval of the most recent
reviewable push" exist together for a reason: without them, an agent could
collect approvals on a harmless diff and then push something else before
the merge fires.

Combined with auto-merge, the normal path for an agent PR is: open it,
collect two approvals, merge with no human involved.

## Current state

Everything above describes the intended arrangement. As of 2026-08-26 it is
not all in place, and the gaps are the silent kind:

- **The ruleset now exists and is enforcing.** `main protection` was
  created on 2026-08-26 and `main` reports `protected: true`. All three
  rules are active: pull request required with 2 approvals, dismiss stale
  reviews on push, code-owner review, approval of the most recent push;
  restrict deletions; block force pushes.
- **Its admin bypass is missing.** The ruleset was created with a
  `RepositoryRole` bypass actor for repository admin. GitHub accepted the
  request, created the ruleset, and **discarded that entry without an
  error** — `bypass_actors` reads `null`. This is the same silent-discard
  behaviour as a CODEOWNERS entry for an account without write access, in a
  different part of the API, and it has a consequence: the escape hatch
  described under *Known sharp edges* for a human-authored guardrail PR is
  not installed. Until it is added, such a PR cannot be merged at all
  rather than merging by deliberate bypass. Adding it via the UI is the
  reliable route, since the UI only offers actors the repository actually
  supports.
- **GitHub added `require_extra_approval_for_unattributed_changes`.** Not
  requested; it is a current default. Despite the general-sounding name it
  is a **Copilot-specific** rule — GitHub presents it as *"require an
  additional approval for unattributed Copilot pull requests"*, and it
  applies when Copilot opens a PR under its App identity with no
  attribution to a person. It does **not** fire merely because a PR was
  authored by a bot account: `@larkbot-codex`, `@larkbot-gemini` and
  `@larkbot-claude` are ordinary user accounts and do not trigger it. Left
  enabled, since it costs this repository nothing and guards a real case if
  Copilot is ever used here.
- **Agent write access is now in place.** Read from the collaborators API
  on 2026-08-26: `@larkbot-codex`, `@larkbot-gemini` and `@larkbot-claude`
  all hold **Write**, and `@thelarklan` holds Admin. This changed during
  the life of this pull request — all three held Read earlier the same day
  — so re-read it rather than trusting this line indefinitely.
- **Auto-merge is disabled at the repository level.**
  `allow_auto_merge` is `false`. Enabling it is one step; opting an
  individual PR into auto-merge is a second, separate one. Neither is done,
  so nothing merges unattended today. That is a separate outstanding target
  from the ruleset, which now exists — the unattended path described under
  *The merge gate* is the part still not built.
- **The previous CODEOWNERS named accounts that do not exist.**
  `@thelarkbot` and `@thelarkdoodle` both 404. Every review request routed
  through them went nowhere, with no error anywhere to notice.

The merge gate is therefore live but incomplete, and review routing still
depends on this pull request merging. Until then, treat review as manual.
The pull-based check described in [`review-checking.md`](review-checking.md) is what makes that survivable:
it looks at reviews and commits directly, so it keeps working while review
requests are still being discarded.

## Known sharp edges

**A guardrail PR opened by the human has no eligible approver.** On
`/.github/workflows/` or `/.github/CODEOWNERS`, `@thelarklan` is the only
code owner — and is excluded as the author. "Require review from Code
Owners" cannot be satisfied by any normal route. Such a PR merges only via
admin bypass. This is a consequence of author-exclusion meeting a
single-owner path, not a misconfiguration, but it does mean every change to
CI or ownership is a deliberate bypass. A guardrail PR opened by an *agent*
is fine: the human is not the author, so the human can approve it.

**Quorum depends on who opened the PR.** With four owners, an agent-opened
PR leaves three eligible approvers for two required approvals, which has
slack in it. A PR the human opens leaves the three agents, and needs two of
them awake. That is the tighter case, and the one to watch: if bypassing
starts happening routinely on human-opened PRs, the required count is too
high for a repository this size and 1 is the honest number.

**Admin bypass is always available.** The human can merge anything. The
ruleset is a guardrail against unattended agent behaviour, not a lock
against the owner. Bypasses are recorded, which is most of their value —
they should stay rare enough to be worth reading.

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
