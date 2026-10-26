# LEGACY (pre-2026-10-26) — the Qwen3-TTS Aiden narrator

The workflow-video-tour default is now **Phonon voice `Alfie`** (see
`steps/3-narration.md`). Phonon accepts no style/instruct text, so the per-beat
`Delivery:` clauses below cannot be reproduced on it; they are kept only for the
legacy `tts-qwen3.py` path.

# Approved narration voice — Aiden + per-beat delivery

Synthetic — no human recording, no personal data. Qwen3-TTS 1.7B **CustomVoice**
preset `Aiden` (`--mode custom --speaker Aiden --stable --instruct ""`, temp 0.9 /
top-k 50 / top-p 0.95, reseeded per beat), with a per-beat `Delivery:` clause carried
on each timeline beat.

Approved by the human on the <KEY> run after an A/B against the rejected Ryan
narration. Chosen over VoiceDesign because design mode draws a new speaker on every
call, so per-beat style text re-rolls the voice (measured LTAS cosine 0.9876 mean /
0.9828 worst); Aiden with these same clauses measured 0.9971 / 0.9960 while still
moving median F0 across 112–136 Hz.

## Base — identical, byte for byte, in every beat

> A neutral General American male voice in his thirties: clear, warm, even-paced,
> no regional accent. A confident software engineer explaining something he just built.

## Per-beat `Delivery:` clause, appended to the base

| beat | appended line |
|---|---|
| b1-context | Delivery: matter-of-fact and brisk — laying out the problem, no drama. |
| b2-before-missing | Delivery: flat and let down, pointing at the gap; ease off and land hard on "missing". |
| b3-after-end | Delivery: bright and pleased — this is the payoff, a notch faster and clearly up on energy. |
| b4-after-either | Delivery: relaxed and explanatory, steady pace, mild warmth. |
| b5-guard | Delivery: careful and precise, treating the caveat as important; slightly slower. |
| b6-close | Delivery: confident and satisfied close, even pace, downward final cadence. |

The beat ids follow the <KEY> storyboard; keep the *shape* of the mapping (problem
beats dry, payoff beats up, guard careful, close settled) for other videos rather than
the literal ids.

## Reproducing it

A beat's own `instruct` (base + clause) overrides the global `--instruct`, so put the
concatenation on the timeline:

```json
{"id": "b3-after-end", "narration": "…", "instruct": "<base> <clause>"}
```

```bash
~/.cache/qwen3-tts/venv/bin/python $S/scripts/tts-qwen3.py \
  --mode custom --speaker Aiden --stable --instruct "" \
  --timeline "$VIDEO_DIR/timeline.json" --out "$VIDEO_DIR/tts-qwen3"
~/.cache/qwen3-tts/venv/bin/python $S/scripts/voice-identity.py "$VIDEO_DIR/tts-qwen3"
~/.cache/qwen3-tts/venv/bin/python $S/scripts/voice-stats.py "$VIDEO_DIR/tts-qwen3"
```

Identity must come back "ok — one speaker" (LTAS ≥ 0.99); the wording steers pitch
only loosely, so accept a spread and check the delivery by ear.
