---
name: whatsapp
description: Send and read messages in WhatsApp Web (the user's personal account) by driving the user's REAL Chrome. Use when the user wants to message someone on WhatsApp, read/send a WhatsApp chat, draft a WhatsApp message, or "open WhatsApp". Triggers include "send a message to <person> on WhatsApp", "open WhatsApp", "draft a WhatsApp reply", "read the <name> chat", "tell <person> ... on WhatsApp".
allowed-tools: Bash(npx agent-browser:*), Bash(agent-browser:*), Bash(curl:*)
---

# WhatsApp Web (personal) via the real Chrome

This skill drives the user's **actual** Chrome (already logged into WhatsApp Web under the **Default** profile) over CDP, using the `agent-browser` skill's bind-mount setup. It never launches an isolated throwaway browser — that would lose the WhatsApp session and trigger CAPTCHAs.

**Prerequisite:** the `agent-browser` skill must already be set up (bind mount at `~/.agent-browser/chrome` + launchers that pass `--remote-debugging-port=9222`). If port 9222 isn't reachable, run the bootstrap first:
```bash
curl -s --max-time 2 http://127.0.0.1:9222/json/version >/dev/null && echo READY   # WhatsApp lives in the Default profile
```

## Mandatory rules (no exceptions)

1. **Always TYPE first, never send without explicit confirmation.** Compose the message into the input box and stop. Show the user the exact text and ask for confirmation (e.g. "send it?"). Only press **Send** (or Enter) after the user says "yes / send / go ahead". This is the single most important rule — an unconfirmed send is a hard error.

2. **Drive the real Chrome via `--auto-connect`.** Every command uses `agent-browser --auto-connect --headed …`. Do NOT launch an isolated `--session`/`--profile` browser. Do NOT use `agent-browser close` / `close --all` — that would quit the user's real Chrome and drop their WhatsApp/other tabs. Just stop issuing commands when done.

3. **WhatsApp Web is in the Default profile.** If a WhatsApp tab isn't open, open one: `agent-browser --auto-connect --headed open https://web.whatsapp.com/` then wait for it to load.

## Core workflow

```bash
# 0. (once) confirm a debuggable Chrome is up — see agent-browser "Attach checklist"
curl -s --max-time 2 http://127.0.0.1:9222/json/version >/dev/null && echo READY

# 1. find / focus the WhatsApp tab (title contains "WhatsApp")
agent-browser --auto-connect --headed tab list
agent-browser --auto-connect --headed tab 0        # switch to the WhatsApp tab (use its index)

# 2. if WhatsApp isn't open yet:
agent-browser --auto-connect --headed open https://web.whatsapp.com/
agent-browser --auto-connect --headed wait --load networkidle

# 3. open a chat by name: type the name in the search box, then click the result
agent-browser --auto-connect --headed snapshot -i                         # get refs (search box is "Search or start a new chat")
agent-browser --auto-connect --headed fill @<searchbox> "<contact name>"   # filter the list by the chat/contact name
agent-browser --auto-connect --headed wait 1000
agent-browser --auto-connect --headed find text "<contact name>" click        # open that conversation
agent-browser --auto-connect --headed wait 1500

# 4. read the conversation: the right pane shows messages; the compose box aria-label is
#    "Type a message to group <name>" (groups) or "Type a message" (1:1)
agent-browser --auto-connect --headed snapshot -i

# 5. DRAFT (type) the message — do NOT send. See compose-box notes below.
# 6. show the user the drafted text and ask for confirmation.
# 7. only after the user confirms: click the Send button (label "Send") to send.
```

### Reading who/what
- The chat list (left pane) shows each chat's name + last-message preview as `gridcell`s. Use `find text "<name>" click` to open a chat.
- After opening, `snapshot -i` shows both the list and the conversation pane (message bubbles + the compose box). Conversation messages appear as elements in the right pane; the compose box is a `textbox` with aria-label `Type a message to group <name>` or `Type a message`.

## Compose box — critical technical notes

WhatsApp's message input is a **rich contenteditable** (`div[contenteditable="true"][aria-label*="Type a message"]`). It fights normal automation:

- **`fill` does NOT clear** — it *appends* to existing text and **strips newlines**. Never rely on `fill` alone to set a message, and never assume the box is empty.
- **`Ctrl+A` selects only one paragraph block**, not the whole box. Repeated `Ctrl+A`+`Delete` is unreliable.
- **Direct DOM / Selection API changes get reverted** by WhatsApp's editor framework. Don't set `innerHTML`/`textContent` or use `deleteFromDocument` — they won't stick.

**Reliable way to draft a message:**

1. Clear the box by **mouse-dragging** across it, then `Delete`:
   ```bash
   # get the box rect
   agent-browser --auto-connect --headed eval --stdin <<'EVALEOF'
   (() => { const el=document.querySelector('div[contenteditable="true"][aria-label*="Type a message"]'); el.focus(); const r=el.getBoundingClientRect(); return JSON.stringify({y:Math.round(r.y),h:Math.round(r.height)}); })()
   EVALEOF
   # drag from top-left to bottom-right, then delete (repeat until textContent length is 0)
   agent-browser --auto-connect --headed mouse move 676 <top>     # x from rect; y = rect.y+2
   agent-browser --auto-connect --headed mouse down
   agent-browser --auto-connect --headed mouse move 1200 <bottom>  # y = rect.y+rect.height-2
   agent-browser --auto-connect --headed mouse up
   agent-browser --auto-connect --headed press Delete
   # NOTE: the box is bottom-anchored and SHRINKS as you delete content, so re-read the rect
   #       before each drag. Repeat until: eval -> String(el.textContent.length) == "0"
   ```
2. **Insert the text with `execCommand('insertText')`** (replaces the current selection / inserts at caret, and goes through the editor properly):
   ```bash
   agent-browser --auto-connect --headed click @<composebox>   # focus
   agent-browser --auto-connect --headed eval --stdin <<'EVALEOF'
   (() => {
     const el = document.querySelector('div[contenteditable="true"][aria-label*="Type a message"]');
     el.focus();
     const msg = "your message here";
     return "inserted:" + document.execCommand('insertText', false, msg) + " len:" + el.textContent.length;
   })()
   EVALEOF
   ```
3. **Newlines get stripped by `insertText`.** Write the message as a **single paragraph** (use commas/spaces, not line breaks). If separate lines are really needed, type line-by-line with **`press Shift+Enter`** between lines — but test carefully, since a plain `Enter` SENDS the message. Default to one paragraph.
4. **Verify** the drafted text with `eval` reading `el.textContent` before showing the user.
5. **Do NOT press Enter** anywhere — Enter sends. Only the Send button (or an explicit `click @<sendbutton>`) sends, and only after confirmation.

### Sending (after confirmation only)
```bash
# locate the Send button (it appears once there's text) and click it
agent-browser --auto-connect --headed snapshot -i | grep 'button "Send"'
agent-browser --auto-connect --headed click @<sendbutton>
# verify: compose box textContent.length == 0 and the new message appears at the top of the conversation
```

## Chat style preferences — sound human, NOT like an AI

When drafting messages on the user's behalf, write the way he actually texts. Don't sound like an AI assistant.

- **Lowercase, casual.** Most messages lowercase. Minimal capitalization.
- **No AI punctuation.** Avoid em-dashes (`—`), Oxford-comma lists, and perfect formal grammar. Commas/periods are sparse.
- **No structured formatting in messages.** No bullet points, no headings, no markdown, no numbered lists inside a chat message. Chat messages are prose, run-on, conversational.
- **Contractions without apostrophes are fine** (`cant`, `dont`, `ill`, `lets`, `tho`, `em` for "them"). Match the user's own texting habits.
- **No assistant phrases.** Never write "I'd be happy to", "Certainly", "Let me know if you need anything else", "Sure, I can help with that", etc. Just say the thing.
- **Tone matches the chat.** Friends/family → loose, warm, emoji as he'd use them. Work/technical → slightly cleaner but still human, not corporate.
- **Keep it short and natural** — a real person sends a quick line, not an essay. Split big news across a couple short messages if it reads better, but remember each is a separate send (so only do that after confirming the whole).
- **Emoji** sparingly and naturally (e.g. 🚀 for excitement), the way he'd actually use them — not as decoration on every line.
- When in doubt, read a few of the user's recent sent messages in that chat (`gridcell "… You : …"` previews) and match that voice.

## Sending files / documents (photos, zips, PDFs, etc.)

WhatsApp Web's "Attach" → "Document" (or "Photos & videos") menu item opens a **native OS file picker dialog** that cannot be controlled via CDP or DOM automation:

- **CDP WebSocket is blocked.** Chrome rejects WebSocket connections to the DevTools endpoint with `403 Forbidden` unless launched with `--remote-allow-origins=*`, which we can't add without restarting the user's real Chrome (forbidden by rule 2).
- **`xdotool`/`wtype` are unreliable** for the native dialog, especially under Wayland.

**The workaround:** clicking the menu item also creates a hidden `<input type="file">` element in the DOM. Even though the native dialog opens, the hidden input is fully accessible via `agent-browser`. Use the `upload` command to set the file programmatically — it calls Playwright's `setInputFiles` under the hood, which bypasses the native dialog entirely.

### File send workflow

```bash
# 1. Click the Attach button to open the menu
agent-browser --auto-connect --headed snapshot -i | grep 'button "Attach"'
agent-browser --auto-connect --headed click @<attachbutton>
agent-browser --auto-connect --headed wait 1000

# 2. Click the desired menu item (Document, Photos & videos, etc.)
agent-browser --auto-connect --headed snapshot -i | grep 'menuitem'
agent-browser --auto-connect --headed click @<documentmenuitem>
# A native file picker dialog opens — IGNORE IT. It can be dismissed with Escape later.

# 3. Tag the hidden file input with an ID so we can target it
#    Document  → input[type=file][accept="*"]  (accepts any file type, multiple)
#    Photos    → input[type=file][accept="image/*"] (accepts images only)
agent-browser --auto-connect --headed eval --stdin <<'EVALEOF'
(() => {
  const inputs = document.querySelectorAll('input[type="file"]');
  for (const el of inputs) {
    if (el.accept === '*' && !el.id) {
      el.id = 'doc-file-input';
      return 'tagged: ' + el.id;
    }
  }
  return 'no untagged document input found';
})()
EVALEOF

# 4. Upload the file via agent-browser's upload command (bypasses native dialog)
agent-browser --auto-connect --headed upload "#doc-file-input" "/absolute/path/to/file.zip"

# 5. Dismiss the native dialog if it's still open
agent-browser --auto-connect --headed press Escape

# 6. Wait for WhatsApp to process the attachment, then verify
agent-browser --auto-connect --headed wait 2000
agent-browser --auto-connect --headed snapshot -i | grep -i -E 'send|caption|type a message'
# You should see:
#   - button "Send N selected"  (the send button, N = number of attached files)
#   - textbox "Type a message"  (caption box — NOT the regular compose box)
#   - button "Open document, <filename>, item N of N"  (the attached file)

# 7. (optional) Add a caption using execCommand('insertText') on the caption box
#    The caption box is a div[contenteditable=true] with aria-label="Type a message"
#    (different from the regular compose box which has aria-label="Type a message to <name>")
agent-browser --auto-connect --headed eval --stdin <<'EVALEOF'
(() => {
  const el = document.querySelector('div[contenteditable="true"][aria-label="Type a message"]');
  if (!el) return 'caption box not found';
  el.focus();
  const msg = "your caption text here";
  return "inserted:" + document.execCommand('insertText', false, msg) + " len:" + el.textContent.length;
})()
EVALEOF
# NOTE: execCommand may report len:0 immediately but the text IS inserted — verify with a second eval.

# 8. Show the user what will be sent (filename + caption) and ask for confirmation.
# 9. After confirmation, click the "Send N selected" button
agent-browser --auto-connect --headed snapshot -i | grep 'button "Send'
agent-browser --auto-connect --headed click @<sendbutton>
# Verify: the caption box disappears and the regular compose box ("Type a message to <name>") is empty.
```

### Key notes for file sending

- **The native dialog is harmless.** It opens but doesn't block DOM access. The `upload` command works regardless of whether the native dialog is open. You can dismiss it with `Escape` before or after uploading.
- **The file input is ephemeral.** It only exists in the DOM after clicking the menu item. Tag it with an ID immediately, then use `upload` right away.
- **Two file inputs may coexist.** WhatsApp keeps an `accept="image/*"` input for photos at all times. The `accept="*"` input appears only after clicking "Document". Match on `accept` to target the right one.
- **The send button changes.** When a file is attached, the regular "Send" button is replaced by "Send N selected" (where N = number of attached files). Use `grep 'button "Send'` to find it — the exact label varies.
- **The caption box is separate from the compose box.** When a file is attached, a caption input appears with aria-label `Type a message` (no contact name). The regular compose box (`Type a message to <name>`) still exists but is not the active input. Use the `Type a message` box for captions.
- **`execCommand('insertText')` may report `len:0`** right after insertion on the caption box, but a follow-up `eval` reading `textContent` will show the text is there. Always verify with a second eval.
- **Absolute file paths are required** for the `upload` command. Relative paths may not resolve correctly.

## Things to never do
- Never send without explicit user confirmation (rule 1).
- Never `agent-browser close` / `close --all` the real Chrome.
- Never launch an isolated `--session`/`--profile` browser for this skill.
- Never set the compose box via `fill` and assume it cleared/replaced — always verify `textContent` afterward.
- Never press `Enter` to send; use the Send button.
- Never try to control the native OS file picker dialog via CDP WebSocket or xdotool — it's blocked. Use `agent-browser upload` on the hidden `<input type="file">` element instead (see "Sending files / documents" section above).
- Never paste the user's sensitive info (passwords, 2FA) into chats.