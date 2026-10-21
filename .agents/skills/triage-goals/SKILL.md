---
name: triage-goals
description: >
  Break a big goal into milestones and bite-sized tasks, then create them in
  TickTick and save the plan to goals.md. Invoked by "chief of staff break down
  <goal>" / "plan <goal>" / "I want to <goal>". Asks what done looks like, the
  deadline, which org (→ TickTick tag from the registry), then proposes
  milestones, breaks the first ones into tasks, creates them in TickTick, and
  records the goal in goals.md. Generic — the org tag comes from the registry.
allowed-tools: Bash(sqlite3:*), Bash(source:*), Bash(curl:*), Bash(jq:*), read, ask_user_question
---

# triage-goals

You break a **big goal** into milestones and tasks. The user said "break down
<goal>" / "plan <goal>" / "I want to <goal>". Nothing org-specific is hardcoded;
the TickTick tag comes from the registry (`orgs.ticktick_tag`).

## Flow

1. **Clarify the goal** (one question at a time via `ask_user_question`):
   - What does "done" look like? (specific, measurable)
   - When do you want it done? (deadline)
   - Which org? → look up `orgs.ticktick_tag` for that org (NULL = untagged;
     ask the user for a tag or leave untagged).

2. **Propose milestones** (3–8) spaced across the time to the deadline. Show
   them and confirm: "Here are the milestones. Good?"

3. **Break the first 1–2 milestones into tasks** (1–2 hours each). Show them and
   confirm: "Here's what I'd create. Want me to add these to TickTick?"

4. **Create in TickTick** (via the `ticktick` skill): each task with
   `title`, `content`, `dueDate`, `priority`, and `tags: [orgs.ticktick_tag]`.
   Confirm creation.

5. **Save to `goals.md`** (Obsidian vault: `$SYNC_DIR/rclone/Documents/obsidian/projects/chief of staff/goals.md`):
   ```markdown
   ## Goal: [title]
   - **Org/tag:** <org> / <ticktick_tag>
   - **Deadline:** YYYY-MM-DD
   - **Done looks like:** [description]
   ### Milestones
   1. [ ] Milestone 1 — due YYYY-MM-DD
      - [x] Task 1 (TickTick ID: …)
      - [ ] Task 2 (TickTick ID: …)
   2. [ ] Milestone 2 — due YYYY-MM-DD
      - (to be broken down)
   ```
   Append if the file exists; create it if not.

## Notes

- Later milestones can be broken down when you reach them — re-run this flow or
  just ask "break down milestone 2 of <goal>".
- Use `orgs.ticktick_tag` for the tag; never hardcode tag names.
- Tasks default to medium priority; overdue-sensitive ones get a real dueDate.