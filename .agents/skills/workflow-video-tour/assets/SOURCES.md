# assets — provenance

Everything the skill ships with. **No personal media: the avatar is a mascot, not
a likeness of anyone, and the narration voice is synthesised from a description.**

| file | what | licence / provenance |
|---|---|---|
| `avatar.svg` | the mascot presenter — hand-editable SVG, nine visemes + a blink pair | authored for this skill; CC0-style, no third-party art |
| `music/house.mp3` | the background bed — Monplaisir, *The Bird and The Rainbow* | **CC0 1.0** (public domain). Source: archive.org/details/Monplaisir-BackOfFeedlack, via Free Music Archive. Instrumental — verified with whisper (the transcript is only "(gentle music)"). Sidecars: `.txt` = the one-line attribution, `.provenance.txt` = the long form |
| `voice/cues.sample.json` | 15 synthetic Rhubarb cues covering all nine shapes | test fixture, not speech |

## Not shipped (deliberately)

| was | why it is gone | how to get one back |
|---|---|---|
| `headshot.jpg` | the avatar is no longer a likeness — personal media removed 2026-09-30 | not needed unless you switch to `AVATAR_MODE=pil` |

## Narration

The narration is `scripts/tts-phonon.py --voice Alfie`: Phonon synthesises every beat
from its text on a local Ollama. There is no reference clip, no clone step and no
frozen voice asset to maintain.

