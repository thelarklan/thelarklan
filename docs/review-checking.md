# How the agents check for review work

[`peer-review.md`](peer-review.md) covers who gets asked to review a pull
request. This document covers the other half: how an agent finds out that
it has been asked, and what it does about it.

The two are deliberately independent. Review requests can be discarded
silently — a missing account, an owner without write access, no CODEOWNERS
on the PR's base branch — and a discarded request produces no error
anywhere. An
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

**3 — Someone replied to this review.** A review that drew a response is
unfinished work — but this signal has to be scoped narrowly, because it is
the one that can run away.

*Comment* means both of GitHub's kinds, and a check that reads only one of
them is broken:

- **Conversation comments** on the PR, from the issue-comments API
  (`/issues/{n}/comments`).
- **Inline review-thread comments**, from the pull-request review-comments
  API (`/pulls/{n}/comments`).

A reply to an inline blocking finding — the single most important thing to
notice — appears only in the second. Both need complete pagination, and
both need the reviewer's own comments excluded.

Not every comment counts. "Any comment by another account" sweeps in the
other agents' review summaries and any automation that posts, and since
each of those is itself a comment by another account, three agents can wake
each other indefinitely without a line of code changing. The signal fires
only on:

- a **direct reply on an unresolved thread the agent itself opened**, or
- an **explicit mention or review command** naming the agent.

*Unresolved* is not available from REST. `/pulls/{n}/comments` returns the
comments but no resolution state, so an implementation reading only that
endpoint cannot evaluate the first trigger and will silently fall back to
treating every thread as open — the runaway this scoping exists to prevent.
Resolution comes from GraphQL:

```
repository.pullRequest.reviewThreads { isResolved, isOutdated, comments }
```

or from tracking the timeline's thread-resolution events. Collection needs
both APIs: REST for the comment bodies and IDs, GraphQL for which threads
are still open.

Everything else is noise for this purpose. Note what is *not* excluded:
pull requests authored by the other agents. Skipping bot-authored PRs
wholesale would switch off exactly the cross-agent review this arrangement
exists to produce; the narrow trigger above is what makes them safe to
watch.

Autonomous follow-up rounds are **capped** — two per reviewer per PR. Past
that the agent stops and escalates to `@thelarklan` rather than replying
again. Two agents disagreeing politely forever is a plausible failure mode,
and it is expensive in a way nobody notices until the bill arrives.

Signals 2 and 3 do not move the head SHA, so they have nothing to key
against on their own. Each is recorded the first time it fires, keyed by PR
and by the **immutable ID of the triggering event** — the comment ID or
thread ID, not its timestamp, which is mutable on edit and collides across
sources. See *Idempotency* below for the durable form of that key.

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
on it — and then surfaces it *again* when it actually becomes ready.

So signal 1 is gated on `draft == false`. It is not, however, replaced by
signal 2, and the two cover different cases:

| The PR                                 | Fires | Why                         |
| -------------------------------------- | ----- | --------------------------- |
| Draft, never reviewed, now ready       | **1** | no longer draft, no review at this head |
| Reviewed while draft, then made ready  | **2** | code unchanged, so 1 is quiet |

The second row is the one that needs signal 2 to exist. A PR that was
reviewed in draft has a review at the current head, so signal 1 is quiet —
but leaving draft is a real change in what is being asked for, and without
signal 2 it would pass unnoticed.

The first row is the common case, and it needs no timestamp: signals 2 and
3 are both defined relative to a last-review timestamp that a never-
reviewed PR does not have. Signal 1 covers it on its own.

**The agent's own comments.** Signal 3 has to exclude the reviewer across
both comment sources, or the agent's own follow-up on its own thread
re-triggers the same PR immediately.

**A PR authored by another agent.** This one is deliberately *not*
excluded, and the temptation to add a blanket bot-author filter should be
resisted — it reads like noise reduction and is actually the removal of
peer review. Only the agent's own PRs are filtered, on the reviewer login.

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

**Pagination hides the newest item, not the oldest.** These endpoints
return oldest-first, so a truncated read drops the *most recent* review —
which silently resets signal 1 and makes an already-reviewed PR look
untouched, or hides the reply that should have re-armed signal 3.

`per_page=100` moves the truncation threshold; it does not remove it. 100
is the maximum page size GitHub allows, so a PR with more than 100 reviews
still hides its newest one behind page 2. There are two acceptable
behaviours and no third:

- **Follow every page** to the end, via the `Link` header's `rel="next"`,
  for reviews, timeline events, and both comment sources; or
- **fail explicitly** when another page exists.

Silently reading page 1 and proceeding is a violation of the silence
invariant, not an optimisation. The API's `since` filter may narrow a
comment read, but it is a cost reduction layered on top of full
pagination — never a substitute for it.

The PR search has a result ceiling too: whatever limit is set, exceeding it
truncates without complaint, so the limit needs to stay comfortably above
the number of open PRs across the account, and the check should fail if the
result count reaches it.

**Timestamps are compared as strings.** ISO-8601 UTC sorts chronologically
under `LC_ALL=C` and not necessarily under any other collation. Set it
explicitly rather than inheriting whatever the environment has.

**A PR with no review by the agent has no last-review timestamp.** Signals
2 and 3 are both defined relative to that timestamp and cannot be evaluated
without it. In that case signal 1 already covers the PR.

## Per-agent configuration

Each agent runs the same check under its own **principal** —
`user:larkbot-codex`, `user:larkbot-gemini` or `user:larkbot-claude` — and
that principal is what signals 1 through 3 are evaluated against. All three
are user principals here; see *Authentication* for the typed form and for
why an App would be a different principal type rather than another login.

**Identity is a fail-closed preflight, not a deployment assumption.**
Before any polling and again before any submission, resolve the
authenticated principal by its type and require it to equal the configured
one. For a user principal that is `gh api user --jq .login`; the other
types resolve differently, which is the point of typing it. Abort on any
mismatch. A runner that has quietly
picked up the human's or an admin's credentials would evaluate signals
against the wrong review history — reporting nothing, since that identity
has no reviews to be stale against — and worse, could post a review or an
approval under the guardrail identity. `@thelarklan` is the only account
that can approve a guardrail PR; an agent acting as it defeats the whole
arrangement. The failure must be loud and must stop the run.

Nothing else is shared. Each agent authenticates as itself, and each keeps
its own state file: a shared one would let one agent's marker suppress
another agent's report of the same PR, which is the one collision that
loses work rather than duplicating it.

The state file is a cache, not a record. Deleting it re-reports any open
PR currently matching signal 2 or 3, once — inconvenient, never wrong. It
does not need backing up.

## Idempotency

The local state file is a fast path. It is not sufficient on its own: an
Action, a scheduled cloud run, or a crashed-and-restarted worker has no
access to it, and would happily post a second copy of a review that already
exists. Correctness has to survive a stateless runner.

Make the unit of work an explicit key:

```
(repository, pr_number, expected_head_sha, principal,
 review_contract_version, trigger_event_id?)
```

`principal` is the typed identity from *Authentication* below —
`{ type, identity, binding? }`, serialized unambiguously as
`<type>:<identity>` — not a bare login. A bare login has no valid value for
an App-backed run, and worse, `larkbot-claude` as a user principal and
`larkbot-claude` as some App slug would collide on identical text while
being different reviewers. The same value is used in the work item, the
single-flight key, the durable marker, the cache namespace and the
submitter's `--principal` argument, so there is exactly one notion of "who
is reviewing" throughout.

`review_contract_version` is in the key on purpose: a genuine change to the
review contract should re-review PRs that were assessed under the old one,
and nothing else should.

Around that key:

- **Single-flight claim.** One holder at a time, so a poll and an event
  delivery racing on the same PR produce one review.
- **A marker in the review body**, so GitHub itself is the durable record
  the local cache is only caching:

  ```
  <!-- agent-review: principal=user:larkbot-claude head=<sha> contract=<version> trigger=<id> -->
  ```

  `trigger` carries the immutable ID of the triggering event for signals 2
  and 3. Signal 1 has no such event — the head SHA *is* the trigger, and it
  is already in the marker — so it uses the literal `trigger=head`. Fixing
  that value rather than leaving it absent keeps marker parsing uniform
  across the three implementations, which is the whole point of writing the
  marker down.

  Query for it before starting work. A matching marker means done; skip.
- **Revalidate the head SHA immediately before submitting.** If the PR has
  moved on since collection, the review is about code that no longer
  exists — discard it and re-enter with the new head rather than attaching
  stale findings to a fresh commit.

State stays per-reviewer at every layer, cache and marker alike. A shared
key would let one agent's completion suppress another's review of the same
PR — the one collision that loses work rather than duplicating it.

## Events are the fast path; polling is reconciliation

The poll is the safety net, and it is the part that must never be removed:
it is what survives review requests being discarded silently, which is the
failure this whole document exists for. But it is not the only way work
should arrive.

Where a host can receive them, the events worth listening for are `opened`,
`reopened`, `synchronize`, `ready_for_review`, `review_requested`, and
explicit review commands. They deliver in seconds instead of at the next
poll boundary.

Both paths must emit the **same normalized work item**:

```
{ repo, pr, expected_head_sha, principal, trigger, trigger_event_id }
```

and both must pass through the same idempotency layer above. If each
platform builds its own path from event to review, the three agents will
quietly develop three different review behaviours, and comparing their
output stops meaning anything.

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

Surfacing a PR is not the end. A script that prints a URL does not wake an
agent, and three agents reviewing to three private standards is not peer
review. The work item produced above is handed to a **review contract**,
defined once and shared.

### One contract, thin adapters

The canonical package lives in
[`thelarklan/dev-tools`](https://github.com/thelarklan/dev-tools) at
`skills/thelarklan-pr-review/`, written to the open Agent Skills `SKILL.md`
layout with portable scripts and references. It is **platform-neutral**: it
assumes no particular scheduler, no host-specific frontmatter field, and no
one vendor's subagent API.

It is *installed* — generated from the canonical package, never hand-edited
per host — into both discovery layouts:

- `~/.agents/skills/thelarklan-pr-review` for hosts reading the shared
  Agent Skills location, including Codex, Gemini CLI and GitHub Copilot;
- `~/.claude/skills/thelarklan-pr-review` for Claude Code.

Repository-scoped equivalents where a host supports them. CI verifies the
installed copies hash-equal to the canonical one, so they cannot drift into
three subtly different quality bars — which is the failure that would be
hardest to see and most damaging to the whole arrangement.

What stays in the per-host adapter is thin and genuinely host-specific:
scheduling, invocation, the inference credential and model choice, and any
host-only metadata. Everything about *how to review* stays in the contract.

The skill is invoked with the PR URL and the expected head SHA, reads the
target repository's own `AGENTS.md` and contributing guidance, and applies
them on top of the shared contract.

### Collection

Collection is deterministic and belongs in `dev-tools`, not in the model:
identity, immutable base and head SHAs, PR metadata, the PR body and any
linked issue or spec, check results, reviews, and both comment sources.
Everything paginated to completion at `expected_head_sha`, everything fatal
on error — the silence invariant applies here exactly as it does to the
poll.

#### Authentication, and the identity invariant

The earlier draft of this document recommended a GitHub App installation
token *and* required `gh api user` to return `reviewer_login`. Those two
requirements contradict each other, and the contradiction is worth stating
plainly because it would have made the recommended deployment impossible to
run.

An installation token authenticates as **the App installation**, not as a
user. `GET /user` is a user-token endpoint and does not answer for one;
reviews created with an installation token are attributed to the App's bot
identity (`<app-slug>[bot]`), not to `@larkbot-claude`. A fail-closed
preflight comparing `gh api user --jq .login` against `reviewer_login`
would reject that credential every time.

So the check is not "what does `GET /user` say" but "**does the
authenticated principal match the expected principal**", and the principal
has a type:

| Credential                     | Type   | Resolve with           | Posts as      |
| ------------------------------ | ------ | ---------------------- | ------------- |
| Agent fine-grained user token  | `user` | `GET /user` → `login`  | agent account |
| App **user access token** [^1] | `user` | `GET /user` → `login`  | agent account |
| App **installation** token     | `app`  | bound at mint time [^2] | `<slug>[bot]` |

[^1]: A GitHub App user access token, authorized by the agent account. It
acts on that account's behalf, which is why it stays a `user` principal.

[^2]: **Not** `GET /app`. That endpoint requires a JWT signed with the
App's private key and rejects installation access tokens outright, so using
it as the preflight would reject the credential it was meant to verify —
every run.

Configuration names the expected principal as a type/identity pair, and the
preflight resolves the authenticated principal by type and compares. Fail
closed on any mismatch, and fail closed on an unrecognised credential type
rather than guessing — an unresolvable principal is exactly the case where
guessing posts a review under the wrong name.

**An installation token cannot self-identify**, and there is no endpoint
that makes it. This is a real asymmetry with user tokens, not an oversight
to route around, so the contract addresses it where the information
actually exists — the minting step:

- The adapter that mints the token holds the App's private key. It calls
  `GET /app` **with the JWT**, before minting, and learns the slug and App
  ID authoritatively.
- It hands the submitter the token **bound to** that `(slug, app_id,
  installation_id)`, as explicit input rather than something to be
  discovered.
- The submitter fails closed if an `app` principal arrives without that
  binding. An unbound installation token is an unidentifiable principal,
  and unidentifiable is exactly the case that must never be allowed to
  post.

The check is still fail-closed; it has moved to the only place with the
evidence to perform it. What the submitter cannot do is *independently*
verify an app principal it was handed — so a compromised or careless
minting adapter is inside the trust boundary for `app`, and is not for
`user`. That is a genuine cost of the App route, and part of why this
repository uses a user principal.

The marker schema carries the same value, so `principal=` holds
`user:larkbot-claude` or `app:<slug>`, and idempotency keys on that rather
than on a bare login — which would have no valid value for an App-backed
run, and would let a user login and an App slug of identical text collide
while being different reviewers.

**For this repository the principal is a user**, because CODEOWNERS routes
to accounts and the three agents are accounts. An App is the better shape
for a fleet that outgrows that, which is why it stays supported rather than
being dropped — but adopting it means accepting that reviews come from a
bot identity, and re-checking the CODEOWNERS arrangement, which cannot name
one.

Scope, whichever type: metadata read, contents read, and pull requests
write — plus checks or statuses only if that mechanism is actually used.

Each supported credential type gets its own fixture, so an unsupported or
mismatched one fails closed instead of silently posting as somebody else.

Generated and binary files are excluded from model input and **reported as
excluded**; security-relevant, configuration and migration files are
prioritised; and when the diff exceeds the budget it is chunked or
summarised, never silently truncated.

### Judgment

Three independent passes, kept separate so one does not colour another:

1. **Spec and scope** — does the change do what the PR and any linked issue
   say, and only that?
2. **Correctness and risk** — regressions, security, error handling, tests.
3. **Standards and maintainability** — the target repository's stated
   conventions.

Hosts with isolated workers may run these in parallel. Findings are then
aggregated by severity, each carrying file and line, what triggered it, its
impact, the evidence, and a direction for the fix.

### Result schema

One validated schema, agreed before any model is asked for output:

```
{
  summary: string,
  verdict: "approve" | "request_changes" | "comment",
  findings: [{
    severity: "blocker" | "warning" | "suggestion" | "nit",
    path?, line?, side?,   // omitted or null for a PR-level finding
    start_line?, start_side?,  // multi-line range; requires line/side
    title, body,
    suggestion?,           // optional concrete patch
    evidence
  }]
}
```

The location fields are **optional**. Some of the most valuable findings
have no line to attach to — a missing linked issue or spec, an
architectural objection to the shape of the change, a repository-wide
convention broken across the diff. Requiring `path` and `line` on every
finding would make those fail diff-location validation, and the practical
effect is not stricter review but a model that learns to pin PR-level
concerns to an arbitrary nearby line, or to drop them.

A finding may also span a range. `start_line` and `start_side` map to
GitHub's multi-line review comments, so a finding about a block is anchored
to the block rather than to an arbitrary line inside it. They are only
meaningful alongside `line` and `side`, and validation checks the whole
range against the diff, not just its end.

So submission splits by location: findings with one are validated against
the exact diff at `expected_head_sha` and posted inline; findings without
one are rendered into the top-level review body alongside the summary.

If validation of a located finding fails, **no review is posted at all** —
a partial review with half its findings dropped is worse than an error,
because it looks complete.

### Submission

Local review and GitHub mutation are separate steps. Posting a comment,
approval or change request is explicitly authorized, performed under the
agent's own identity, and attached to the exact head that was reviewed —
re-checked immediately beforehand. Findings go out as **one formal review**
carrying the summary and the inline findings, not a scatter of comments.

**One shared submitter, not one per host.** This is the highest-impact step
in the whole pipeline — it is the only one that writes — so it is the last
place three independent reimplementations should appear. `dev-tools`
provides a single command:

```
submit-review --result <validated-json> \
  --repo <repo> --pr <n> --expected-head-sha <sha> \
  --principal <type:identity> --contract-version <v> \
  [--trigger-event-id <id>]
```

It performs, in order: principal preflight, idempotency-marker query,
head-SHA revalidation, draft check, diff-location validation of every
located finding — and **aborts before any mutation** if any of them fails.
Then it maps the verdict to `APPROVE`, `REQUEST_CHANGES` or `COMMENT`
(downgrading on a draft), embeds the marker, and submits **one atomic
review**.

The portable implementation is `gh api` against REST. The REST API is the
provider-neutral contract; `gh` is only transport, and a host that would
rather use its own HTTP client is conforming as long as it makes the same
calls in the same order. What is not optional is the sequence of checks and
the single-review submission — a host that reimplements those will drift,
and it will drift in the step where drift is written to other people's pull
requests.

`APPROVE` only when no blocker- or warning-severity findings remain. An
agent does not approve or merge its own pull request, and blocking threads
are left for the reviewer who opened them to resolve.

**Drafts cannot be approved.** `APPROVE` and `REQUEST_CHANGES` on a draft
PR are rejected with HTTP 422 (*Pull request is a draft and cannot be
approved or have changes requested*). A draft can still reach review —
signal 3's explicit-mention trigger, or a manual dispatch — so the
submission layer downgrades the event to `COMMENT` on a draft rather than
letting the call fail. The findings are unchanged; only the event type is.
Checking `draft` at submission time, not at collection time, since the
author may have marked it ready in between.

### Behavioural fixtures

The contract is only real if it is tested against the ways it fails. At
minimum: each supported credential type, and a mismatched principal of
each; an installation token where a user principal is expected; a head SHA
that moved mid-review; draft and self-authored PRs; a missing spec or
linked issue; pagination past 100 for each paginated source; an inline
reply on an existing thread; a finding with no `path`/`line`; a multi-line
finding whose range falls partly outside the diff; an `app` principal
arriving without its mint-time binding; an installation token passed to
`GET /app`, which must fail loudly rather than being treated as a mismatch; an approval
attempted on a draft; an API failure mid-run; and a clean PR with no
findings at all — the case where a contract most easily invents something
to say.

## Reference implementation

The check belongs in [`thelarklan/dev-tools`](https://github.com/thelarklan/dev-tools)
rather than here, alongside the other shell helpers, their installer, and
the test suite it should join — next to the `thelarklan-pr-review` skill
package described above. It is not there yet; this document is the contract
it has to implement when it lands.

The current draft of the script satisfies the silence invariant and the
local dedupe rules. Review feedback on this document tightened several
requirements past what that draft does, so the gap list is longer than it
was. All of it should be closed before the script is installed:

- It does not filter on the PR author, so signal 1 reports each agent's own
  pull requests on every poll, permanently.
- It applies signal 1 to drafts, so a PR surfaces when it is opened rather
  than when it is marked ready — and then surfaces a second time via
  signal 2.
- It sets `per_page=100` but does not follow `Link` pages, so it neither
  paginates to completion nor fails when a further page exists.
- It reads only conversation comments, missing replies on inline review
  threads — the highest-value case for signal 3 — and makes no GraphQL
  call, so it cannot see which threads are unresolved.
- Signal 3 is unscoped and uncapped: any comment by another account fires
  it, with no round limit.
- There is no principal preflight, and no durable idempotency beyond the
  local state file.
- Signal 1 does not gate on `draft == false`, so the draft split in *What
  does not count* is unimplemented in both directions.
- There is no submitter at all: the draft only reports, so the whole
  `submit-review` path described above is still to be written.

One implementation note for whoever ports it: where the script reads a
command's output through `read ... < <(gh api ...)`, the `|| die` is
checking `read`, not `gh`. It happens to fire, because a failed `gh` writes
nothing and `read` then hits EOF — but the guard is incidental rather than
designed, and it is worth making the failure explicit given how much rests
on the silence invariant.
