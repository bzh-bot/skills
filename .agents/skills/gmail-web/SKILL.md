---
name: gmail-web
description: >
  Read and act on Gmail via agent-browser driving the user's real Chrome in a
  specified profile. Use when asked to read, send or triage Gmail in the browser.
  The caller passes the Chrome profile and the expected signed-in email address;
  always verify the signed-in account matches before acting, and never close the
  user's Gmail tab. Decisions about what to do with each message (reply, task,
  unsubscribe, leave) belong to the calling flow — this skill provides the
  Gmail-web mechanics only.
allowed-tools: Bash(agent-browser:*), Bash(npx agent-browser:*), Bash(sleep:*), Bash(curl:*), read
---

# Gmail (web)

Drive Gmail in the user's real Chrome via the `agent-browser` skill. The caller
specifies **which Chrome profile** and **which signed-in email** to expect.

**Gotchas (Google sign-in):**
- **Bot wall / "Couldn't sign you in"**: if Google blocks the automated sign-in, relaunch the worker's Chrome with `--disable-blink-features=AutomationControlled` (CDP re-attach keeps `navigator.webdriver=false`) and retry the password fill.
- **"This browser or app may not be secure"**: Chrome with `--remote-debugging-port` gets OAuth-flagged by Google. For the shared/host profile the fix is to pre-authenticate on the host by running plain `google-chrome --user-data-dir=<profile-dir>` (no debugging flags), logging in, then closing — the worker's Chrome then picks up the authenticated session. For isolated worker profiles, prefer a keyring lookup (`secret-tool` on Linux, Keychain on macOS) + `agent-browser fill` over interactive OAuth.

**Per-account mode (isolated launch):** when the caller runs one browser per
account, do NOT auto-connect. Launch an isolated headed Chrome per account
instead (`AGENT_BROWSER_SESSION=<account>-<accountId>` +
`--profile ~/.agent-browser-profiles/<account>-<accountId>`, persistent per
account) and verify the signed-in account matches the expected identifier — the
profile needs a one-time Google login on first run.

## Golden rules

1. **Always open a NEW tab** — never navigate the user's existing tabs.
2. **Verify the signed-in account** matches the email the caller specified (the
   Google account avatar top-right shows the address) before reading or acting.
   If the wrong account is signed in, tell the caller and stop.
3. **Never close the user's Gmail tab.** When done, stop issuing commands and
   leave the tab open.
4. **Confirm before sending.** Never send/reply without explicit approval from
   the calling flow.

## Setup (once per session)

```bash
curl -s --max-time 2 http://127.0.0.1:9222/json/version >/dev/null && echo READY   # agent-browser "Attach checklist"
agent-browser --auto-connect --headed open "https://mail.google.com/mail/u/0/"
agent-browser --auto-connect --headed wait --load networkidle
sleep 3
agent-browser --auto-connect --headed snapshot
```
If the profile has multiple Google accounts, pick the right `u/<N>` index for the
expected email. Verify the signed-in address via the avatar before proceeding.

## Binding a tab: pin once, then pass `--pin-tab` alone

When a flow hands you a pre-opened labelled tab (or you opened your own), bind the
session to that one tab **once**, then keep the pin sticky:

```bash
# 1. bind ONCE — `--pin-tab tab tN` also selects the tab (tN, or a label)
agent-browser --auto-connect --session S --pin-tab tab t3

# 2. every later command: `--pin-tab` followed by the subcommand, no tab tN
agent-browser --auto-connect --session S --pin-tab snapshot
agent-browser --auto-connect --session S --pin-tab eval 'document.title'
```

**Gotcha:** `--pin-tab tab tN` consumes the following
subcommand, so a trailing `eval` or `snapshot` on that same command line returns
only the tab envelope. Bind on its own invocation first (step 1), then run every
command as `--pin-tab <subcommand>` with no `tab tN` (step 2). `--pin-tab` is
sticky per session; once pinned, commands fail with a `tab_gone` error rather
than falling back to another tab.

## List unread only

Gmail has no "Unread" folder; use the search box with `is:unread`:

```bash
# Focus the search box, type the query, submit
agent-browser --auto-connect --headed eval '(() => {
  const i = document.querySelector("input[aria-label=\"Search mail\"], input[name=\"q\"]");
  if (!i) return "no search box";
  i.value = "is:unread";
  i.form && i.form.submit();
  return "searched";
})()'
agent-browser --auto-connect --headed wait --load networkidle
sleep 2
agent-browser --auto-connect --headed snapshot
```
The message list now shows unread threads (newest first by default — Gmail web
search can't reliably sort oldest-first; work top to bottom).

## Open an email & read it

Click a thread row (`tr` / `[role="listitem"]` in the message list) to open it in
the reading pane. Read the body from the message content container:

```bash
agent-browser --auto-connect --headed eval '(() => {
  const a = document.querySelectorAll("[data-message-id] .a3s, .ii.gt div, .a3s.aiL");
  return a[a.length-1]?.innerText?.slice(0, 4000) ?? "(body not found)";
})()'
```
(Sender/subject/time are in the open-message header.)

## Mark as read

Gmail marks a thread read when you open it. To mark read without opening, use the
toolbar: select the row's checkbox, then click the "Mark as read" toolbar button
(envelope icon). For a batch, select-all + "Mark all as read".

## Send / reply / draft

- **Reply:** open the thread, click **Reply**, type in the compose body
  (`div[aria-label="Message Body"]`), and **stop** — show the draft to the user
  and only send after explicit confirmation. Send with the Send button (not a
  keyboard shortcut) to be safe.
- **New message:** click **Compose**, fill To/Subject/body the same way.
- **Drafting only** (no send) is the safe default; the calling flow decides.

## When you're done

Leave the Gmail tab open. Stop issuing agent-browser commands. Report what you
did (counts, actions) to the calling flow.

## Notes / known limits

- Gmail web search results are newest-first; there's no reliable oldest-first
  toggle in the UI. Work newest-first and say so in the wrap-up.
- Selectors above are a starting point; Gmail's DOM changes — re-derive from the
  snapshot (`aria-label` attributes are the stable anchors) if they don't match.