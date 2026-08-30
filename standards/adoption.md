# Adopting the review standard

Each consumer repository keeps a small `docs/review-policy.md` with these exact
declarations near the top:

```text
Standard: review-standard-v2
Approval profile: peer-agents
Human owner: @thelarklan
```

`Approval profile` is either `peer-agents` or `human`. A personal
`peer-agents` repository uses the hardened App contract in the standard: two
native approvals, a head-pinned agent-identity check, required CI and ownership
rules, and GitHub auto-merge. The rest of the file records:

- required local and CI verification commands;
- repository-specific manual verification;
- protected or high-risk paths beyond the standard minimum;
- the corresponding private App protected-path configuration and its audit;
- merge and post-merge cleanup behavior; and
- exceptions in the format required by the standard.

The repository also keeps local `CODEOWNERS`, branch protection or ruleset
configuration, CI integration, and the canonical pull-request template. Those
are implementation controls, not alternate policy sources.

## Synchronizing the template

From a checkout of this repository, run:

```bash
bash scripts/sync-review-standard.sh /path/to/consumer
```

Use `--check` in CI or audits to detect drift without changing the consumer:

```bash
bash scripts/sync-review-standard.sh --check /path/to/consumer
```

The check validates the v2 adoption declarations, requires the local policy and
`CODEOWNERS`, and confirms that an effective ownership rule names the declared
human owner. It cannot verify account access, App permissions, auto-merge, or
the live ruleset; audit those controls separately. Synchronization changes only
the managed pull-request template; it does not overwrite repository-specific
policy or ownership.

Adopt upgrades through a focused pull request. Update the managed template,
review the new normative contract, update the declaration, document any new
exception, and then update the rollout matrix.
