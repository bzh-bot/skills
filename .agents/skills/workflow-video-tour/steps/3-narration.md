# V3 — Narration → `tts/<beat>.wav`

**Default: `--mode custom --speaker Aiden` plus a per-beat `Delivery:` clause** —
the human-approved narrator. The approved base voice text and the six per-beat
clauses live in [`assets/voice/aiden-narration.md`](../assets/voice/aiden-narration.md);
a timeline beat carrying its own `instruct` overrides the global flag.

`--instruct ""` is load-bearing: the flag's default is `DEFAULT_INSTRUCT`, the
Australian-engineer persona, and in `custom` mode that string is forwarded to
`generate_custom_voice` — omitting it silently colours the preset's delivery. The
empty string makes the script send `None`, which is what the bare preset means.

Run it in a cage (see `/tmp/workflow-cage-setup-needs.md` for the image-level gaps):

```bash
export QWEN3_ROOT=~/.cache/qwen3-tts   # ~/.local/share is read-only in the cage
export LD_LIBRARY_PATH=/tmp/nvlib:$LD_LIBRARY_PATH   # nvidia userspace driver, if not shipped
export TORCH_DISABLE_NATIVE_JIT=1     # no C compiler in cage → triton JIT fails
~/.cache/qwen3-tts/venv/bin/python $S/scripts/tts-qwen3.py \
  --mode custom --speaker Aiden --stable --instruct "" \
  --timeline "$VIDEO_DIR/timeline.json" --out "$VIDEO_DIR/tts-qwen3"
~/.cache/qwen3-tts/venv/bin/python $S/scripts/voice-identity.py "$VIDEO_DIR/tts-qwen3"
```

Aiden is a "sunny American male, clear midrange" — the only English-native male
preset besides Ryan; the remaining seven presets are zh/ja/ko native. **Ryan is
rejected as a narrator** (user decision) — do not re-introduce it.
`Warning: flash-attn is not installed…` on load is expected — `--attn sdpa` (the
default) works fine; do not chase it.

Checkpoint needed: `Qwen3-TTS-12Hz-1.7B-CustomVoice` (4.3 GB) for this default path
— a cage shipping `custom` needs 4.3 GB, not the 12.9 GB of all three models
(`-VoiceDesign` only for design mode, `-Base` only for clone mode).

## Why clone, and not design mode, per video

**Design mode draws a NEW speaker on every call.** Six beats therefore came out as
six different people — while every pitch statistic still looked fine, which is how it
got shipped once. `voice-identity.py` catches it; measured on the PR-290 beats:

| route | LTAS cosine (mean / worst) | verdict |
|---|---|---|
| design mode, one call per beat | 0.9742 / 0.9450 | **different speakers** — the defect |
| **clone from `voice.wav`** | **0.9970 / 0.9953** | one speaker |
| each beat vs the reference itself | 0.9929 | it is the approved voice |

Measured per beat vs the reference: F0 81–120 Hz against the reference's 94 Hz (the
deep register survives the clone), pace 2.2–2.8 words/s overall.

The identity test is `scripts/voice-identity.py`: it reports LPC formants (F1/F2),
the long-term average spectrum, and the LTAS cosine similarity between every pair.
**>= 0.99 is one speaker, <= 0.97 is audibly a different person.** F0 alone cannot
tell you this — that is the whole lesson.

**Per-beat delivery needs a preset, not a design.** `generate_voice_design` takes no
speaker reference, so a per-beat style text re-rolls the speaker: with the identity
sentence held identical and only a `Delivery:` clause varying, design mode measured
LTAS 0.9876 mean / 0.9828 worst, while `--speaker Aiden` with the *same* clauses
measured 0.9971 / 0.9960 and still moved median F0 across 112–136 Hz. Clone mode is
no answer either — `generate_voice_clone` accepts no `instruct` argument, so it
cannot steer delivery at all, and it needs the separate 4.3 GB `-Base` model.

## Replacing the voice (do this rarely, and listen)

1. Design a new one: `tts-qwen3.py --mode design --stable --instruct "<description>"`.
   Measure its delivery with the energy metrics below; iterate on the words.
2. **Listen to a full line.** Metrics cannot tell you whether the character is right.
3. Freeze the approved take as `assets/voice/voice.wav` (+ `.txt` whisper transcript,
   + update `.provenance.txt` with the exact prompt). Re-run `voice-identity.py` on a
   real beat set to confirm the clone is consistent.

## Why `--stable`

The package samples at temp 0.9 / top-k 50 with no seed, so six per-beat calls
drift audibly (measured median F0 138→189 Hz). `--stable` builds the clone prompt
once, samples at temp 0.7 / top-k 30 / top-p 0.95 / rep-pen 1.1, reseeds per beat,
and rejects repeat-runaway takes (one low-temp take produced 655 s for a 15 s
line; budget = words/2.2 × 2.5, 4 attempts). `--x-vector-only` was measured no
better — don't.

**Sizing is measured, never a words-per-second constant.** Measured Ryan pace on
the <KEY> beats was 1.9–3.2 words/s *depending on the line* (digits spelled out
are slow; 27-word lines took 10.2–10.9 s, 19-word lines 10.2 s). After TTS,
re-check every beat's freeze against the ≤ ~1 s hold rule (see steps/1-storyboard.md
checks) — a beat that needed no hold at storyboard time can need one once the voice
is real. Shorten the line and re-voice when the freeze goes over budget; never trim
the clip (rule from the compose-video defect).

`voice-stats.py`: spread of per-beat median F0 < 20 Hz = one narrator; > 35 Hz =
retune or use a longer neutral reference. The 10 s ref beats the 4 s one
(a punchline is a poor fingerprint).

## Fallbacks (human-chosen only — never descend silently)

Standing policy across the workflow-do skills: **never substitute a fallback on your own.** If the default voice backend is unavailable, STOP and ASK the user — and the question must surface the specific blocker, the specific alternatives *with their costs*, and the default-fix option first, then accept a no. A menu that only offers escape hatches without "fix the default" is still steering the human. Record the choice in the run env; a fallback only happens after explicit human authorisation; `TOUR_SKIP_NOTE`-style vars likewise only ever follow a human gate.

The concrete no-GPU gate reads:

> qwen3-TTS needs CUDA, and this cage has no usable GPU (`torch.cuda.is_available() == False` / no `libcuda.so`). Options:
> 1. fix the cage's GPU (extract the NVIDIA userspace driver per `/tmp/workflow-cage-setup-needs.md`), then continue with the default qwen3 voice (~X min)
> 2. narrate with **kokoro** instead (CPU, ~40 s, different voice — a real downgrade: no cloning/design)
> 3. skip the video (with an explicit skip note)
> 4. something else
>
> The user may well say no — the point is that they are asked, not that fallback occurs.

The table below is therefore a menu of **documented options a human can pick**, not an autonomous escalation chain:

| when | command | tag |
|---|---|---|
| GPU busy / qwen venv broken | `uv run --with kokoro-onnx --with soundfile python $S/scripts/tts-kokoro.py --timeline … --out … --voice bm_george` (CPU, ~40 s) | `kokoro/bm_george` |
| draft / smoke test | `$S/scripts/tts-piper.sh --timeline … --out …` (instant, robotic) | `piper/en_GB-alan-medium` |
| a one-off voice you are auditioning (never for a real video — see the defect above; a per-beat instruct re-rolls the speaker too) | `tts-qwen3.py --mode design --stable --instruct "…"` | `qwen3-design/…` |
| the approved narrator (see the base + per-beat clauses above) | `tts-qwen3.py --mode custom --speaker Aiden --stable --instruct ""` | `qwen3-custom/Aiden` |
| another of the 9 preset timbres | `tts-qwen3.py --mode custom --speaker <name> --stable --instruct ""` | `qwen3-custom/<name>` |

## Making a clean reference from a real recording (only for cloning a human)

`make-reference-clip.sh` slices 3–15 s out of a recording, ranks 10 s windows by
loudness when `--start` is omitted, loudnorms to −18 LUFS and writes a whisper
transcript (clone mode needs `--ref-text`). Copy large media local first — `~/gdrive`
is an rclone mount that drops mid-read.

```bash
$S/scripts/make-reference-clip.sh --video recording.MOV --out /tmp/ref.wav --duration 10
```

Never clone a person's voice without their explicit consent, and say in the PR body
whose voice it is.

## Checks

- [ ] one WAV per beat that has narration; durations ≈ words/2.8 (no runaway take)
- [ ] **`voice-identity.py` → "ok — one speaker"** (LTAS cosine ≥ 0.99). This is the
      check that matters most; a per-beat pitch spread is fine, an identity change is
      not. A failure usually means design mode (or a per-beat instruct fed to it) —
      re-render on a preset speaker.
- [ ] `voice-stats.py` for the per-beat pitch picture
- [ ] listen to two beats back to back — they must sound like the same person

Do **not** `silenceremove` tails (it cuts at the first pause); V4 fits the video
to the voice instead.
