# V3 — Narration → `tts/<beat>.wav`

**Engine: Phonon** (Gradium TTS, Apache-2.0) on a local Ollama, through its
OpenAI-compatible `/v1/audio/speech` route. **Voice: `Alfie`** (user-approved
2026-10-26). There is no second narration engine in this skill.

**In a cage there is nothing to install** — `cage-base` bakes Ollama 0.40.11 with the
MLX overlay and the `phonon` model under `/opt/ollama-phonon`, and its `ENV` carries
`PATH`, `LD_LIBRARY_PATH`, `OLLAMA_MODELS` and `PHONON_VOICE=Alfie`.
`install-phonon.sh` notices the baked runtime and just starts it (containers have no
systemd session, so it uses `setsid nohup … serve`), taking ~3 s.

Measured, for choosing where to run it: in-cage MLX manages ~27 s per line (plus a
~90 s model load on the first call) while a host Ollama answers in **0.7 s**. So when a
host runtime is reachable, point the stage at it — the cage still works standalone:

```bash
# preferred when the host serves Phonon (much faster)
export PHONON_HOST=http://host.docker.internal:11499
# otherwise the baked in-cage runtime, started on demand
$S/scripts/install-phonon.sh --check
python3 $S/scripts/tts-phonon.py --check      # runtime + model + one spoken line
python3 $S/scripts/tts-phonon.py \
  --timeline "$VIDEO_DIR/timeline.json" --out "$VIDEO_DIR/tts" --voice Alfie
python3 $S/scripts/voice-stats.py "$VIDEO_DIR/tts"     # per-beat pitch picture
```

`PHONON_HOST` overrides the server (default `http://127.0.0.1:11434`, else
`$OLLAMA_HOST`); `PHONON_VOICE` sets the voice. No venv, no GPU: 13 s of narration
renders in ~1.2 s on CPU.

## What Phonon does NOT do (verified against 0.40.11)

- **No style/delivery input.** There is no instruct equivalent. A beat that carries
  an `instruct` clause still narrates — `tts-phonon.py` warns once and drops it. To
  change a beat's energy, **rewrite the line**; there is no knob.
- **No speed control.** `speed: 1.25` → `400 only speed 1 is supported`. Pace is the
  voice's own; if a beat is too long, cut words.
- **No mp3.** `response_format` is `wav` or `pcm` only.
- **No seed.** `seed` is accepted and ignored — two identical requests differ in
  bytes. Duration is stable to the frame, so timing checks stay meaningful.
- **No cloning.** The voice list is the whole toolkit; there is no reference-audio
  path and no voice asset to freeze.
- **Linux needs the MLX overlay.** Without it the pull fails with
  `this model requires MLX support, but the MLX runtime is not available`.
  `install-phonon.sh` downloads and overlays it; do not hand-assemble this.

**Streamed WAV headers lie.** Ollama streams the audio, so the `data` chunk length is
`0xFFFFFFFF` and naive readers report absurd durations (measured: 89 478 s for a 5 s
take). `tts-phonon.py` rewrites a truthful header on every file; if you use another
client, normalise before measuring.

## Sizing is measured, never a words-per-second constant

Measured on the beat sets: 17–18-word lines land at **5.4–5.8 s** (≈ 3 words/s), a
5-word line at 1.9 s. After TTS, re-check every beat's freeze against the ≤ ~1 s hold
rule (see steps/1-storyboard.md) — a beat that needed no hold at storyboard time can
need one once the voice is real. Shorten the line and re-voice when the freeze goes
over budget; never trim the clip.

The runaway guard in `tts-phonon.py` rejects a silent take or one far longer than the
text can justify (`max(8 s, words/2.6) × 2.5`, 3 attempts).

## Changing the voice (rare — and listen to it)

1. List the voices: `ollama show phonon | sed -n '/Voices/,$p'` — 40+ Gradium voices;
   names are case- and accent-insensitive.
2. Render the *same* line in each candidate and listen:
   ```bash
   for v in Alfie Easton Preston Trevor; do
     python3 $S/scripts/tts-phonon.py --text "<a real beat>" \
       --out-file /tmp/voice-$v.wav --voice "$v"
   done
   ```
3. **Listen to a full line.** Metrics cannot tell you whether the character is right.
4. Freeze the pick as `PHONON_VOICE` in `settings.env` and record it in the run env as
   `VIDEO_NARRATION="phonon/<voice>"`.

Voice identity is a non-issue: one `voice` value is one speaker. `voice-identity.py`
(LTAS cosine ≥ 0.99) is therefore a sanity check, and `voice-stats.py` reports the
per-beat pitch picture — a spread under 20 Hz median F0 is normal.

## When Phonon cannot run (ask the human — never substitute)

Standing policy across the workflow-do skills: **never substitute a fallback on your
own.** If the runtime is unavailable, STOP and ASK — surfacing the exact blocker, the
costs, and the fix first:

> Phonon needs Ollama ≥ 0.40.9 with the MLX runtime and the `phonon` model (112 MB).
> `scripts/install-phonon.sh --check` fails here: `<exact message>`. Options:
> 1. install/refresh it (`scripts/install-phonon.sh`, ~1.5 GB download, ~2 min), then continue
> 2. skip the video (with an explicit skip note)
> 3. something else
>
> The user may well say no — the point is that they are asked, not that a fallback
> occurs.

## Checks

- [ ] one WAV per beat that has narration; durations ≈ words/3.0 (no runaway take)
- [ ] `tts-phonon.py --check` passes, and every beat's header reports a sane duration
- [ ] `voice-stats.py` for the per-beat pitch picture
- [ ] listen to two beats back to back — same person, and the energy fits the beat
- [ ] no beat relies on an `instruct` clause (Phonon ignores it)

Do **not** `silenceremove` tails (it cuts at the first pause); V4 fits the video to
the voice instead.
