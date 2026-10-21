# V6 — Music → `<slug>-final.mp4`

Music is **always on**. Instrumental, ~24 dB under the voice, ducked further while
the narrator speaks, faded in/out.

```bash
S=~/.agents/skills/workflow-video-tour; SLUG="${TICKET_ID}-${FEATURE_TAG}"
TRACK=$(ls $S/assets/music/*.mp3 | head -1)     # the house track (see below)
$S/scripts/add-music.sh --video "$VIDEO_DIR/$SLUG-avatar.mp4" --music "$TRACK" \
  --out "$VIDEO_DIR/$SLUG-final.mp4" --bed-db -24 --duck 8
MUSIC_ATTRIBUTION="$(cat "$TRACK.txt")"          # → PR body
```

`VIDEO_MUSIC="<track file>"`. Cost: < 30 s.

## The house track (`assets/music/`)

One or two vetted instrumentals live in `assets/music/<track>.mp3` with a sidecar
`<track>.mp3.txt` = `Title — Artist · URL · Licence`. Reuse them; only shop for a
new one when the human asks.

**Free sources, in order** (read the licence on the track page every time):

| source | licence reality |
|---|---|
| freemusicarchive.org | CC0 → use freely; CC-BY → attribute in the PR body; **never NC/ND** for a client repo |
| dig.ccmixter.org | mostly CC-BY-NC — personal repos only; check each track |
| zapsplat.com | free tier requires attribution + account |
| artlist.io / motionarray.com | paid subscription, no attribution; only if the org already pays |

Never: YouTube rips, "no copyright" compilations, anything without a citable page.

**Pick:** instrumental, 70–100 BPM, no drop or build, low-mid energy (pad,
pluck, light piano, minimal drums), ≥ 90 s so it fades rather than loops, mood
neutral-positive. Save the licence page text next to the mp3.

## How the mix works (`add-music.sh`)

`volume=-24dB` resting bed → `sidechaincompress` with the narration as trigger
(ratio 8, attack 15 ms, release 400 ms) → `amix normalize=0` (keeps the voice
level) → `alimiter 0.95`. `--bed-db -20` is more present, `-28` subliminal.

## Checks

- [ ] `volumedetect` mean still ≈ −20 dB; voice clearly on top during speech
- [ ] bed audible in the intro card and the gaps, fades out at the end
- [ ] `MUSIC_ATTRIBUTION` set when the licence is CC-BY / Zapsplat
