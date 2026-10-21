# R7 — Verify + publish

**→ TaskUpdate: R7 → in_progress**

## 7.1 Verify — `workflow-video-tour/steps/7-verify-attach.md` is the authority

```bash
S=~/.agents/skills/workflow-video-tour
FINAL="$VIDEO_DIR/$SLUG-final.mp4"
bash $S/scripts/verify-video.sh "$FINAL" \
  --timeline "$VIDEO_DIR/timeline.json" \
  --video-json "$VIDEO_DIR/video.json"
```

It fails on: no audio stream, mean < −35 dB, more than 3 silences ≥ 2 s, or a
`--timeline`/`--video-json` path that does not exist. It writes
`$VIDEO_DIR/contact-sheet.png`.

**Two length-specific readings of that output:**

- **`> 40 MB` is a WARN, and it is expected here.** That warning is about GitHub's
  ~100 MB *user-attachment* limit. A release asset may be 2 GB, which is where this video
  is going, so a 60–120 MB file is fine. Investigate only a >2× overshoot (lower CRF/FPS
  in R5). Do not re-render a 90 MB video down to 38 MB to silence a warning.
- **More than one ≥2 s silence is a real failure at this length.** With narrated dividers
  the only silent stretch is the 4 s intro card. Two or more means a card beat is missing
  its narration WAV, or a captured beat is shorter than its line and froze. Both are fixed
  in R4/R5, not here.

**Look at the contact sheet.** It is one frame per beat, and at 27 beats it is the only
cheap way to catch the mistakes that survive every automated check: a box on the wrong
element, a divider whose bullets overflow, a "BEFORE" beat showing the new UI. The colour
test proves a box was drawn; only your eyes prove it is on the right thing.

## 7.2 Chapters → `<slug>-chapters.txt`

A 4-minute video is long enough that people scrub. GitHub renders `MM:SS  Title` lists in
a code block as chapters, and it costs one `jq`. Mark the intro and the **card beats
only** — a marker per beat is noise, and beat ids like `c3-card` are not titles anyone
wants to read.

```bash
jq -r -n \
  --slurpfile v "$VIDEO_DIR/video.json" \
  --slurpfile t "$VIDEO_DIR/timeline.json" \
  --slurpfile s "$VIDEO_DIR/storyboard.json" '
  ($s[0].beats | map({key: .id, value: (.heading // .caption // .id)}) | from_entries) as $title
  | ([ $t[0][] | select(.segment == null) | .id ]) as $cards
  | [ $v[0].beats[] | . as $b
      | select($b.id == "00-title" or ($cards | index($b.id)))
      | { at: ($b.start | floor),
          label: (if $b.id == "00-title" then $s[0].title else ($title[$b.id] // $b.id) end) } ]
  | .[] | "\(.at)\t\(.label)"' \
  | awk -F'\t' '{ printf "%02d:%02d  %s\n", $1/60, $1%60, $2 }' \
  > "$VIDEO_DIR/$SLUG-chapters.txt"
cat "$VIDEO_DIR/$SLUG-chapters.txt"
```

**Check the file, do not assume it.** A list reading `03:12  c3-card` means `heading` is
missing from a divider in the storyboard — go back to R2 rather than shipping it.

## 7.3 Publish — the GitHub Release, not the PR body

**Release asset, not `--attach`.** `gh pr edit --attach` puts the file in
`user-attachments`, size-capped and tied to one PR. A release asset is the permanent,
org-visible home for a release video, and the release body is where the release notes
already live.

```bash
ORG_REPO=$(jq -r '.repo.slug // empty' "$VIDEO_DIR/release-manifest.json")
TAG="${RELEASE_TAG:-$(jq -r '.release.fromTag // empty' "$VIDEO_DIR/release-manifest.json")}"
URL="https://github.com/$ORG_REPO/releases/download/$TAG/$SLUG-final.mp4"
DUR=$(( $(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$FINAL" | cut -d. -f1) ))

# 1. the body: the generated notes, or the existing release body with any old video block stripped
if gh release view "$TAG" --repo "$ORG_REPO" >/dev/null 2>&1; then
  gh release view "$TAG" --repo "$ORG_REPO" --json body -q .body > "$VIDEO_DIR/body.base.md"
  awk '/^## / { skip = ($0 == "## 🎬 Release video") } !skip' \
    "$VIDEO_DIR/body.base.md" > "$VIDEO_DIR/body.base.clean.md"
else
  cp "$VIDEO_DIR/release-notes.md" "$VIDEO_DIR/body.base.clean.md"
fi

# 2. prepend the video block
{
  echo "## 🎬 Release video"; echo
  echo "**[$TAG walkthrough]($URL)** · $((DUR / 60))m$((DUR % 60))s"; echo
  echo "<details><summary>Chapters</summary>"; echo
  echo '```'; cat "$VIDEO_DIR/$SLUG-chapters.txt"; echo '```'; echo
  echo "</details>"; echo
  if [ -n "${MUSIC_ATTRIBUTION:-}" ]; then echo "🎵 $MUSIC_ATTRIBUTION"; echo; fi
  cat "$VIDEO_DIR/body.base.clean.md"
} > "$VIDEO_DIR/body.new.md"

# 3. upload the asset FIRST (a body linking a 404 is worse than no body), then set the body
gh release upload "$TAG" "$FINAL" --repo "$ORG_REPO" --clobber
gh release edit   "$TAG" --repo "$ORG_REPO" --notes-file "$VIDEO_DIR/body.new.md"
curl -sIL -o /dev/null -w '%{http_code}\n' "$URL"
```

If the repo has **no releases at all** and you are not authorised to create one, fall back
in this order — and say which one you used in the handoff:

1. `gh release create "$TAG" --repo "$ORG_REPO" --title … --notes-file …` (needs write
   access; **ask before inventing a tag**)
2. attach to the release PR body (`gh pr edit --attach`) — fine under ~100 MB
3. write the MP4 to `~/Desktop/<slug>/` and hand over the path

A non-GitHub remote (GitLab, Forgejo, Bitbucket) has no `gh`: use fallback 3, and put the
chapters file next to the video.

## 7.4 Write the outcome back

```bash
cat >> "$VIDEO_DIR/RUN.env" <<EOF
VIDEO_PATH="$FINAL"
VIDEO_URL="$URL"
VIDEO_DURATION_S="$DUR"
VIDEO_SIZE_MB="$(( $(stat -c%s "$FINAL") / 1048576 ))"
VIDEO_CHAPTERS="$(grep -c . "$VIDEO_DIR/$SLUG-chapters.txt")"
VIDEO_MUSIC="$(basename "${MUSIC_FILE:-none}")"
RELEASE_TAG="$TAG"
ORG_REPO="$ORG_REPO"
EOF
```

## Checks

- [ ] `verify-video.sh` **OK** — no FAIL; the >40 MB WARN read and consciously accepted
- [ ] the contact sheet was looked at, beat by beat — not skipped because the colour test
      passed
- [ ] exactly one ≥2 s silence in the whole file
- [ ] `durationS` within 10 s of `budget.json.measuredS`, and inside 200–290 s
- [ ] chapters reference real headings, not beat ids, and the first entry is `00:00`
- [ ] the asset is downloadable and the body's link returns 200/302 (the `curl -w` above)
- [ ] no second video block if an earlier render already published one
- [ ] `release-notes.md` and the published body agree — the notes were generated in R1,
      *before* you knew which chapters made the cut, so reconcile them
- [ ] `RUN.env` written; `$VIDEO_DIR` kept (a re-cut or a re-voice must never need a
      re-capture)

**→ TaskUpdate: R7 → completed**
