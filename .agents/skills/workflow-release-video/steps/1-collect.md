# R1 — Collect → `release-manifest.json`, `release-notes.md`

**→ TaskUpdate: R1 → in_progress**

```bash
S=~/.agents/skills/workflow-release-video
REPO="${REPO:?set REPO}"                  # any repo, any host
VIDEO_DIR="${VIDEO_DIR:-$REPO/.release-video}"
mkdir -p "$VIDEO_DIR"

node $S/scripts/collect-release.mjs \
  --repo "$REPO" \
  --from "${RELEASE_FROM:-}" --to "${RELEASE_TO:-HEAD}" \
  --fetch \
  --name "${PRODUCT_NAME:-}" \
  --out "$VIDEO_DIR/release-manifest.json" \
  --notes "$VIDEO_DIR/release-notes.md"
```

`--fetch` is not optional in practice: a clone that has not pulled in weeks is the most
common cause of an empty range, and the script will **refuse** rather than hand you a
manifest of PRs that are not in it.

## What it does

- **Range** = newest tag reachable from `--to`, or `--from` if given, or a `--since`
  window when the repo has never been tagged.
- **PRs** = `gh pr list --state merged` when the remote is GitHub and `gh` is authed,
  kept only if the merge commit is *in* `rangeShas` — merge date alone is a guess on a
  long-lived base branch, and membership also drops cherry-picks.
- **Fallback** = the `(#123)` suffix on squash-merge subjects, so a GitHub-less or
  offline repo still gets numbered items.
- **Grouping hints** = `byArea` (conventional scope → top-level dir → type),
  `byType`, and `smallAreas` — the areas with one lonely item, which R2 must fold into
  the closing chapter rather than give a beat each.
- **`release-notes.md`** = a grouped markdown draft. This is prose for a human, and
  later the skeleton of the GitHub Release body.

## Checks

- [ ] `jq .confidence` is `high` (a `low` means the commit set was unusable and the
      filter fell back to merge dates — re-run with `--fetch`, or pass an explicit
      `--from`/`--to`)
- [ ] `jq .stats.prs` is non-zero and plausible for the window; if `gh` returned nothing,
      `jq .source` is `git-log` and the items came from squash subjects
- [ ] `jq .release.fromTag` is the tag you expect (not `null` on a repo that has tags —
      that means the tag is not reachable from `--to`)
- [ ] `jq .stats.commitsWithoutPr` is small relative to `.stats.commits`; a large number
      means the PR metadata is missing and the notes are built from raw commits
- [ ] `jq .groupingHints.byArea` has a shape a human would recognise as areas of this
      product — if it is one giant bucket named after a directory, the repo does not use
      conventional commits and R2 must group by hand
- [ ] read the first 40 lines of `release-notes.md` yourself — this is the story you are
      about to tell, and it is the last cheap moment to notice it is the wrong range

## Traps

- **A shallow clone is not an error state, it is a wrong answer.** `git rev-parse
  --is-shallow-repository` → `true` means `rangeShas` is incomplete; the script sets
  `confidence: low` and filters by merge date. Re-run with `--fetch`.
- **Monorepo areas.** `packages/*` and `apps/*` collapse to `packages/x`, not
  `packages`, so a workspace-based repo still gets usable areas.
- **Forgejo / GitLab / Bitbucket remotes have no `gh`.** The script detects the remote
  and skips `gh` silently for non-GitHub hosts; the manifest is `git-log`-sourced and
  `confidence` stays `high` when the range itself is sound.
- **Never hand-write the manifest.** If `collect-release.mjs` cannot see the release,
  the release is not visible, and a hand-written JSON will make the video assert things
  nobody can check.

**→ TaskUpdate: R1 → completed**
