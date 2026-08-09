# Land a pull request that arrived on the GitHub mirror

> **How-to (Diataxis).** Outside contributions arrive as pull requests on the GitHub
> mirror, but the canonical repository is the Forgejo instance. This guide is the
> procedure for reviewing such a PR and landing it on the trunk so that GitHub marks it
> **Merged** automatically and the contributor keeps full authorship — without creating a
> Forgejo account for them.

## The setup, and why it constrains the procedure

```
git.embersescape.party/maartene/InkSwift   ← canonical trunk (origin)
                 │
                 │  Forgejo push mirror, ONE WAY
                 ▼
github.com/maartene/InkSwift               ← mirror; where PRs and issues arrive
```

Three consequences follow from this, and every step below exists because of one of them:

- **GitHub's `main` is a downstream copy.** The push mirror force-pushes, so anything
  written directly to the GitHub repo is overwritten on the next sync.
  **Never use GitHub's merge button** — the merge would be clobbered and the PR would
  revert to open with its commits gone from `main`.
- **The mirror is one way.** Nothing needs to flow GitHub → Forgejo at the server level;
  you fetch PR branches directly from GitHub in your own clone. A pull mirror is *not*
  needed and would fight with the repo being your writable trunk.
- **GitHub decides "Merged" by SHA reachability.** It flips a PR to Merged when the exact
  head SHA of the PR becomes reachable from the base branch. So the merge must
  **preserve the contributor's commit SHAs** — no rebase, no squash, no cherry-pick.

## Procedure

### 1. Fetch the PR branches into your clone

`refs/pull/*` are GitHub-generated read-only refs; no remote needs to be configured.

```sh
git fetch https://github.com/maartene/InkSwift.git \
  'refs/pull/11/head:refs/prs/11' \
  'refs/pull/12/head:refs/prs/12'
```

### 2. Review each PR in isolation

Build a throwaway worktree per PR and run the same gate CI enforces. Worktrees keep the
main working tree untouched and let you compare against a clean baseline.

```sh
git worktree add /tmp/pr11 refs/prs/11 --detach
cd /tmp/pr11 && swiftlint lint --strict --no-cache --config .swiftlint.yml && swift test
```

Record the baseline test count on `main` first, so you can confirm the PR's claimed test
delta. Verify behavioural claims against `inklecate` directly rather than trusting the
description — see [`native-compile-story-equivalence.md`](native-compile-story-equivalence.md).
Clean up with `git worktree remove --force /tmp/pr11`.

### 3. Merge, preserving SHAs

Land them one at a time. The first can fast-forward; later ones produce merge commits,
which is the price of the automatic Merged label and worth paying:

```sh
git merge --ff-only refs/prs/13
git merge --no-ff refs/prs/11 -m "Merge PR #11: <title>

Fixes #9. Contributed by <Name> (@<login>) via the GitHub mirror,
https://github.com/maartene/InkSwift/pull/11"
```

If two PRs touch the same lines, resolve the conflict **in the merge commit** — that still
preserves both parents' SHAs. Record the resolution in the commit message.

### 4. Re-run the gate on the merged trunk

Individually-green PRs can still interact. Confirm before pushing:

```sh
swiftlint lint --strict --no-cache --config .swiftlint.yml
swift test
for n in 11 12 13; do
  git merge-base --is-ancestor "$(git rev-parse refs/prs/$n)" main \
    && echo "PR $n reachable" || echo "PR $n NOT reachable — GitHub will not mark it merged"
done
```

### 5. Push and sync

```sh
git push origin main
```

Then hit **Synchronize Now** on the Forgejo push mirror if you don't want to wait for the
timer. The PRs flip to Merged on GitHub once the sync lands.

### 6. Reply on the GitHub PR

The contributor lives on GitHub, so review findings, the landed SHA, and the reasons any
referenced issue stays open all belong in a PR comment there. Anything not fixed by the
PR should become its own issue rather than an unrecorded remark.

## Attribution — nothing extra required

Git's `author` field is plain text in the commit object and needs no account on either
host. Merging preserves `author` and rewrites only `committer`, so:

- **Forgejo** shows the contributor's name on their commits (no avatar or profile link,
  since they have no account there — this is the only cosmetic loss).
- **GitHub** gives full contributor credit — contributors list, commit-history avatar,
  contribution graph — provided the commit's author email is one linked to their GitHub
  account, which is normally the case for a commit they pushed themselves.

`Co-authored-by:` trailers are unnecessary here; they matter only if you squash, which
this procedure never does.

## If you deliberately want a linear trunk instead

Rebasing each PR onto `main` keeps history linear but rewrites SHAs, so GitHub cannot
match them: the PRs stay open and you close them by hand with a comment naming the landed
commit. The contributor still keeps author attribution and contribution-graph credit —
only the badge reads grey *Closed* rather than purple *Merged*. Prefer the merge-commit
route unless linearity matters more than the contributor's signal.
