# V3 — Narration → `tts/<beat>.wav`

**Default: Phonon voice `Alfie`** (user-approved 2026-10-26), synthesised through a
local Ollama's OpenAI-compatible `/v1/audio/speech` route. Phonon is Gradium's
text-to-speech family (43M parameters, Apache-2.0) shipped by Ollama ≥ 0.40.9.

```bash
$S/scripts/install-phonon.sh                 # once per machine (sudo); --user for a
                                             # user install on port 11435
python3 $S/scripts/tts-phonon.py --check     # runtime + model + one spoken line
python3 $S/scripts/tts-phonon.py \
  --timeline "$VIDEO_DIR/timeline.json" --out "$VIDEO_DIR/tts" --voice Alfie
python3 $S/scripts/voice-stats.py "$VIDEO_DIR/tts"    # pitch picture
```

`PHONON_HOST` overrides the server (default `http://127.0.0.1:11434`, then
`$OLLAMA_HOST`); `PHONON_VOICE` sets the voice. The script needs **no venv and no
GPU** — it is stdlib Python over HTTP, and 13 s of narration renders in ~1.2 s on
CPU.

## Why Phonon replaced Qwen3-TTS

| | Qwen3-TTS 1.7B (retired) | **Phonon** |
|---|---|---|
| install | 4.3 GB checkpoint + torch venv | **112 MB model**, no venv, no torch |
| compute | CUDA, or slow CPU (`--device cpu`) | CPU or GPU, ~11× real time |
| speaker control | per-beat sampling drift had to be pinned (`--stable`, `--instruct`) | **`voice` IS the speaker** — same value, same person, every call |
| style/delivery | `instruct` text, preset speakers | **none** (see below) |

## What Phonon does NOT do (verified against 0.40.11)

- **No delivery/style input.** There is no `instruct` equivalent. A timeline beat
  that still carries an `instruct` clause narrates fine — `tts-phonon.py` warns once
  and drops it. To change a beat's energy, **rewrite the line**; there is no knob.
- **No speed control.** `speed: 1.25` → `400 only speed 1 is supported`. Pace is the
  voice's own; if a beat is too long, cut words.
- **No mp3.** `response_format` is `wav` or `pcm` only.
- **No seed.** `seed` is accepted and ignored — two identical requests differ in
  bytes. Duration is stable to the frame, so timing checks stay meaningful.
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

## Replacing the voice (do this rarely, and listen)

1. List the voices: `ollama show phonon | sed -n '/Voices/,$p'` — 40+ Gradium voices,
   names case- and accent-insensitive.
2. Render the *same* line in each candidate to a scratch directory and listen:
   ```bash
   for v in Alfie Easton Preston Trevor; do
     python3 $S/scripts/tts-phonon.py --text "<a real beat>" \
       --out-file /tmp/voice-$v.wav --voice "$v"
   done
   ```
3. **Listen to a full line.** Metrics cannot tell you whether the character is right.
4. Freeze the pick as `PHONON_VOICE` in `settings.env` and record it in the run env
   (`VIDEO_NARRATION="phonon/<voice>"`). Update `assets/voice/` provenance if the
   reference clip is replaced.

Voice identity is a non-issue in Phonon — one `voice` value is one speaker — so
`voice-identity.py` (LTAS cosine ≥ 0.99) is now a sanity check rather than the
gate it was under Qwen's sampling. `voice-stats.py` still reports the per-beat pitch
picture; a spread under 20 Hz median F0 is normal.

## Fallbacks (human-chosen only — never descend silently)

Standing policy across the workflow-do skills: **never substitute a fallback on your
own.** If the default voice backend is unavailable, STOP and ASK the user — the
question must surface the specific blocker, the specific alternatives *with their
costs*, and the default-fix option first, then accept a no. Record the choice in the
run env.

The concrete no-runtime gate reads:

> Phonon needs Ollama ≥ 0.40.9 with the MLX runtime and the `phonon` model (112 MB).
> `scripts/install-phonon.sh --check` fails here: `<exact message>`. Options:
> 1. install/refresh it (`scripts/install-phonon.sh`, ~1.5 GB download, ~2 min), then continue
> 2. narrate with **kokoro** instead (CPU, different voice — a real downgrade)
> 3. skip the video (with an explicit skip note)
> 4. something else
>
> The user may well say no — the point is that they are asked, not that fallback occurs.

| when | command | tag |
|---|---|---|
| **the approved narrator** | `tts-phonon.py --timeline … --out … --voice Alfie` | `phonon/Alfie` |
| another Phonon voice (audition only — freeze the pick first) | `tts-phonon.py … --voice <name>` | `phonon/<name>` |
| draft / smoke test | `$S/scripts/tts-piper.sh --timeline … --out …` (instant, robotic) | `piper/en_GB-alan-medium` |
| Phonon runtime unavailable, human approved | `uv run --with kokoro-onnx --with soundfile python $S/scripts/tts-kokoro.py --timeline … --out … --voice bm_george` | `kokoro/bm_george` |
| legacy: Qwen venv still present and the human prefers it | `tts-qwen3.py --mode custom --speaker Aiden --stable --instruct ""` | `qwen3-custom/Aiden` |

## Making a clean reference from a real recording (only for cloning a human)

`make-reference-clip.sh` slices 3–15 s out of a recording, ranks 10 s windows by
loudness when `--start` is omitted, loudnorms to −18 LUFS and writes a whisper
transcript. Copy large media local first — `~/gdrive` is an rclone mount that drops
mid-read.

```bash
$S/scripts/make-reference-clip.sh --video recording.MOV --out /tmp/ref.wav --duration 10
```

Never clone a person's voice without their explicit consent, and say in the PR body
whose voice it is.

## Checks

- [ ] one WAV per beat that has narration; durations ≈ words/3.0 (no runaway take)
- [ ] `tts-phonon.py --check` passes, and every beat's header reports a sane duration
- [ ] `voice-stats.py` for the per-beat pitch picture
- [ ] listen to two beats back to back — same person, and the energy fits the beat
- [ ] no beat relies on an `instruct` clause (Phonon ignores it)

Do **not** `silenceremove` tails (it cuts at the first pause); V4 fits the video
to the voice instead.
