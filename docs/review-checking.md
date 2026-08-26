# How the agents check for review work

[`peer-review.md`](peer-review.md) covers who gets asked to review a pull
request. This document covers the other half: how an agent finds out that
it has been asked, and what it does about it.

The two are deliberately independent. Review requests can be discarded
silently — a missing account, an owner without write access, CODEOWNERS on
the wrong branch — and a discarded request produces no error anywhere. An
agent that waits to be told will wait forever without ever learning that
something is wrong. So the agents **poll**, and they poll against commits
and reviews rather than against notifications, because those are the facts
that survive a broken routing setup.

## The question a poll answers

> Which open pull requests across `thelarklan/*` need a review from me
> right now?

"Right now" is the load-bearing part. A PR that needs review must surface
**once** when it becomes reviewable, and again each time it genuinely
changes — not on every poll in between, which trains the reader to ignore
the output.

## What counts as needing review

Three signals. Any one of them makes a PR actionable.

**1 — Not yet reviewed at the current head.** Compare the PR's head SHA
against the commit SHA of the agent's most recent review of that PR.
Different means the agent has not reviewed the code as it now stands.

This signal keys itself. New commits move the head SHA, so an updated PR
re-arms with no bookkeeping, and a reviewed PR stops reporting the moment
the review lands. Nothing has to be remembered between polls.

**2 — It left draft after the review.** A `ready_for_review` timeline
event with a timestamp later than the agent's last review. The code did not
change; its status did. This is the normal path in these repositories,
where PRs open as drafts and are marked ready only once checks pass.

**3 — Someone replied after the review.** A comment by any account other
than the agent, created after the agent's last review. A review that drew a
response is unfinished work.

Signals 2 and 3 do not move the head SHA, so they have nothing to key
against. Each is recorded in a state file the first time it fires, keyed by
PR, reason, and the timestamp of the triggering event. Without that they
would report on every poll for as long as the PR stays open.

## What does not count

These are the cases that make a check noisy, and noise is how a check stops
being read.

**A PR the agent authored.** Signal 1 fires on it permanently — an author
never has a review at their own head, so the condition is true forever and
can never be cleared. GitHub already excludes the author from review
requests; the check has to apply the same exclusion, by filtering on the
PR's author login, or each agent spends every poll being told to review its
own work.

**A draft.** Signal 1 must respect draft state. A draft is not a request
for review: it is a PR whose author has explicitly said it is not ready,
and by convention here has checks still to run. Reporting on head SHA alone
surfaces every PR the instant it is opened, days before anyone wants eyes
on it — and then signal 2 surfaces it *again* when it actually becomes
ready. Signal 2 is the correct trigger for a draft; signal 1 should skip
drafts entirely.

**The agent's own comments.** Signal 3 has to exclude the reviewer, or the
agent's own follow-up comment on its own review re-triggers the same PR.

## The silence invariant

**Printing nothing must mean "nothing needs review". It must never mean "a
call failed."**

This is the one rule not to trade away for convenience. A check that skips
a repository it could not reach produces exactly the same empty output as a
genuinely quiet morning, and the difference only becomes visible when a PR
has sat unreviewed for hours. There is no alert for it, because from the
outside nothing happened.

In practice:

- Every API call is fatal on error. No `|| continue`, no `2>/dev/null`, no
  defaulting a failed lookup to an empty result.
- A failure exits loudly with the repository and PR it died on, so the
  cause is in the output rather than inferred from an absence.
- A verbose mode reports how many PRs were examined, so a healthy quiet
  poll and a broken one can be told apart without waiting for the
  consequences.

An agent that cannot complete its check should say so and stop. It must not
report "nothing to do".

## Details that decide correctness

**Pagination hides the newest item, not the oldest.** Reviews and timeline
events must be fetched with `per_page=100`; the default of 30 drops the
most recent review on a PR that has been through several rounds, which
silently resets signal 1. Comments should use the API's `since` filter so
the server does the narrowing and the newest comment cannot hide behind a
first page. The PR search has a result ceiling too — whatever limit is set,
exceeding it truncates without complaint, so the limit needs to stay
comfortably above the number of open PRs across the account.

**Timestamps are compared as strings.** ISO-8601 UTC sorts chronologically
under `LC_ALL=C` and not necessarily under any other collation. Set it
explicitly rather than inheriting whatever the environment has.

**A PR with no review by the agent has no last-review timestamp.** Signals
2 and 3 are both defined relative to that timestamp and cannot be evaluated
without it. In that case signal 1 already covers the PR.

## Per-agent configuration

Each agent runs the same check under its own identity — `larkbot-codex`,
`larkbot-gemini`, or `larkbot-claude` — as the reviewer login that signals
1 through 3 are all evaluated against.

Nothing else is shared. Each agent authenticates as itself, and each keeps
its own state file: a shared one would let one agent's marker suppress
another agent's report of the same PR, which is the one collision that
loses work rather than duplicating it.

The state file is a cache, not a record. Deleting it re-reports any open
PR currently matching signal 2 or 3, once — inconvenient, never wrong. It
does not need backing up.

## Cadence

A poll costs one search plus two to four REST calls per open PR. Across the
handful of repositories here that is tens of calls, against a budget of
5,000 per hour per token, so cadence is not constrained by rate limits at
any sane interval. Five minutes is a reasonable default; the dedupe rules
above are what make a frequent poll cheap to read, since a poll with
nothing new prints nothing at all.

The three agents do not need to be staggered. They are independent readers
of the same state, and two agents reviewing the same PR is the intended
outcome — the merge gate asks for two approvals.

## What happens after a PR surfaces

Surfacing a PR is where this check ends. What to do with it is the target
repository's business: follow its `AGENTS.md` or contributing guide, review
against its stated required checks, and leave blocking threads for the
reviewer who opened them to resolve. An agent does not approve or merge its
own pull request.

## Reference implementation

The check belongs in [`thelarklan/dev-tools`](https://github.com/thelarklan/dev-tools)
rather than here, alongside the other shell helpers, their installer, and
the test suite it should join. It is not there yet; this document is the
contract it has to implement when it lands.

The current draft of the script satisfies the silence invariant, the
pagination requirements, and the dedupe rules, and diverges from this
document in two places that should be closed before it is installed:

- It does not filter on the PR author, so signal 1 reports each agent's own
  pull requests on every poll, permanently.
- It applies signal 1 to drafts, so a PR surfaces when it is opened rather
  than when it is marked ready — and then surfaces a second time via
  signal 2.

One implementation note for whoever ports it: where the script reads a
command's output through `read ... < <(gh api ...)`, the `|| die` is
checking `read`, not `gh`. It happens to fire, because a failed `gh` writes
nothing and `read` then hits EOF — but the guard is incidental rather than
designed, and it is worth making the failure explicit given how much rests
on the silence invariant.
