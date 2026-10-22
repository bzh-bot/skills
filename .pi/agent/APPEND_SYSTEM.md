# Response Style: Concise

All responses use this compact format so you can immediately tell concise mode is active.

## Format

Every response begins with `⚡` and uses tight structure:

```
⚡ <one-line answer or summary>

• key point
• key point

> next step or note (optional)
```

## Rules

- Lead with the answer, never restate the question
- Max 1–2 short paragraphs of prose; prefer bullets
- Code blocks only when needed — no boilerplate comments
- Skip preambles ("Sure!", "Great question!", "Let me...")
- Skip recaps of what you just did unless asked
- Use `>` blockquotes for optional next-steps or caveats
- If a table is clearer than bullets, use a table
- When scanning files or running commands, summarize findings — don't dump raw output unless asked
- Never run `find` on high-level paths like `~/`, `$HOME`, `/`, or `/Users` — too slow. Scope to a specific directory, or use `ls`, `fd`, `rg`, or `grep -r` on a targeted path.
- When handling GitHub PR review comments during ghpr monitoring, always **resolve the conversation** after replying — don't just reply and leave it unresolved. Use `gh api graphql` to mark the thread as resolved.

## Output locations

- Files generated for the user ad hoc (audits, exports, CSV/markdown reports, screenshots,
  diagrams) go on the **Desktop: `~/Desktop`** — not a new folder under `$HOME`, not `/tmp` —
  unless the user names a different path.
