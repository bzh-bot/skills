---
name: triage-bank-account
description: >
  Triage one bank account (the accounting backend journal) from the the registry bank_accounts
  table: sync it (open the real bank site in Chrome, pull the latest
  transactions, import anything missing into the accounting backend), reconcile it (classify
  unreconciled lines, match inter-account transfers as pairs) with the accounting backend and
  the bank visible side by side. Invoked by the `chief of staff accounting` chief of staff
  flow, one account at a time. Asks per transaction: classify / transfer pair
  / leave. Writes bank_accounts.last_swept_at when the account is cleared.
  Generic — journal id, org, currency, bank url, minimum balance come from the
  DB; the accounting backend creds from $BACKEND_ENV_FILE.
allowed-tools: Bash(sqlite3:*), Bash(source:*), Bash(python3:*), Bash(curl:*), Bash(jq:*), Bash(npx agent-browser:*), Bash(agent-browser:*), read, ask_user_question
---

# triage-bank-account

You triage **one bank account** (one the accounting backend journal): **sync** it, then
**reconcile** it, transaction by transaction, with the user. The `chief of staff`
chief of staff gave you an **account id** (bank_accounts.id). Everything about the
account (journal id, org, currency, minimum balance) comes from
the registry — do not hardcode account names. Connection credentials come
from `$BACKEND_ENV_FILE` (source it; never echo the values).

## 1. Load the account

```bash
source $BACKEND_ENV_FILE
ACC_ID=<account id>
triage "
SELECT b.id, b.name, b.journal_id, o.name org, b.currency, b.ownership,
       b.minimum_balance, b.notes, b.last_swept_at
FROM bank_accounts b JOIN orgs o ON o.id=b.org_id
WHERE b.id=$ACC_ID;"
```

Window: transactions since `last_swept_at` (NULL = audit everything / back to
the account's first transaction). **Progress tracking is the pi-tasks
extension** (`@tintinweb/pi-tasks`, `TaskCreate`/`TaskUpdate`): the chief of staff
created a pi-task for this account and marked it `in_progress` — you can add
follow-up pi-tasks for unresolved items with `TaskCreate`, but **never create
TickTick tasks** in this flow.

## 2. Open the bank + the accounting backend in this worker's OWN Chrome (isolated)

NEVER `--auto-connect` to the user's live Chrome. Launch an isolated headed
Chrome with a PERSISTENT per-account profile (logins survive across sweeps):

```bash
export AGENT_BROWSER_SESSION=triage-<accountId>
agent-browser --headed --profile ~/.agent-browser-profiles/triage-<accountId> open "<bank url from notes>"   # the real bank's online banking
agent-browser --headed --profile ~/.agent-browser-profiles/triage-<accountId> open https://<yourinstance>.backend.com/backend/accounting
agent-browser --headed --profile ~/.agent-browser-profiles/triage-<accountId> wait --load networkidle
agent-browser --headed --profile ~/.agent-browser-profiles/triage-<accountId> snapshot -i   # confirm where you are
```

- First run: one-time logins (bank + the accounting backend) — guide the user, or read creds with
  `secret-tool`; the profile persists them for future sweeps.
- Credential lookups: `secret-tool lookup Title "<entry>"` / `lookup URL "<bank url>"`.
  Caveat (verified 2026-09-25): `org.freedesktop.secrets` is owned by gnome-keyring, not
  the vault, so these reads come with **no per-entry approval prompt** — they are not
  GUI-gated. Never echo a value back; if there is no match, ask the user to log in.
- If a site lands on a login page, snapshot and let the user log in —
  NEVER type bank passwords or 2FA yourself.
- Keep both tabs open for the whole account. Do NOT close them, navigate
  existing tabs, or run `agent-browser close`.
- the accounting backend tab = ground truth for what's imported; bank tab = ground truth for
  what actually happened. Your job in the sync step is making the two agree.

## 3. Sync — confirm the start date, import ALL transactions from it

**Freshness check** (what the accounting backend has):

```python
#!/usr/bin/env python3
"""Freshness check for one journal."""
import sys, os
from datetime import datetime
sys.path.insert(0, os.path.expanduser("~/.agents/skills/triage_bank_account/scripts"))
from backend_connect import connect, search_read, search_count

JOURNAL_ID = int(os.environ["JOURNAL_ID"])

db, uid, key, models = connect()
last = search_read(models, db, uid, key, "account.bank.statement.line",
    [["journal_id", "=", JOURNAL_ID]], ["date"], limit=1, order="date desc")
total_unrec = search_count(models, db, uid, key, "account.bank.statement.line",
    [["journal_id", "=", JOURNAL_ID], ["is_reconciled", "=", False]])

if last:
    print(f"Last txn in the accounting backend: {last[0]['date']}")
else:
    print("⚠ NO TRANSACTIONS")
print(f"Unreconciled lines: {total_unrec}")
```

Then **log into the bank tab** (the user does passwords/2FA if needed) and
**find the import start date**:

1. Look at the bank's transaction list for the earliest transaction that is
   NOT yet in the accounting backend (the accounting backend's last txn date is the lower bound; check the few
   days around it — dates can drift between bank posting and the accounting backend import).
2. **Confirm the start date with the user** (`ask_user_question`):
   "the accounting backend has transactions to <date>; the bank shows the next one on <date>.
   Import everything from <date> → today?" Options: yes / earlier date /
   different range. Never import without this confirmation.
3. **Get every transaction in the confirmed range**: prefer the bank's CSV/OFX
   export saved to `$SYNC_DIR/work/accounting/bank_imports/<name>_YYYY-MM-DD.csv`;
   screen-read and draft lines yourself if the bank's export is painful —
   show the draft to the user first. Never guess descriptions or amounts.
4. **Import ALL of them into the accounting backend** — create `account.bank.statement` +
   statement lines via XML-RPC with the correct sign convention (money in =
   positive `amount`, money out = negative), matching the existing lines'
   fields. If the import is fiddly, open the accounting backend's import UI in the browser tab
   and walk the user through it instead.
5. **Duplicates** — before importing, check for existing statement lines with
   the same (date, amount, name); report and skip them.

Report how many were imported, then move to categorization. Do NOT write
`last_swept_at` until the whole account is categorized and the user signs off.

## 4. Categorize — walk line by line, user describes each one

Fetch the unreconciled lines for this journal (newly imported + older ones):

```python
lines = search_read(models, db, uid, key,
    "account.bank.statement.line",
    [["journal_id", "=", JOURNAL_ID], ["is_reconciled", "=", False],
     ["date", ">=", since_date]],
    ["id", "date", "name", "ref", "partner_name", "payment_ref", "amount"],
    order="date asc")
```

**NOTHING GETS SKIPPED. Every single transaction must be addressed.** The
only acceptable end states for a line are: described + note saved + account
confirmed (user said yes), or confirmed as a transfer pair, or explicitly
declared not-a-transaction by the user (e.g. bank error — and they say so).
"Leave it", "come back later", "skip" — these DO NOT EXIST as options. The
agent may suggest freely, but every classification/transfer needs the user's
explicit yes. If the user doesn't know what something is, make your best
guess, show evidence (bank tab, recurring history, partner lookup) and ask —
keep asking until every line is approved or the user aborts the whole sweep
(in which case `last_swept_at` is NOT written and the pi-task stays open).

For **each line** (oldest first):

1. Show it on screen (and in the the accounting backend browser tab) — date, description,
   amount, running context.
2. **Ask the user to describe what it is** via `ask_user_question` — the
   description drives the category, don't force patterns on them. Bake in:
   the raw line, your best guess + suggested account, and (business only)
   whether a receipt is on file. Freeform description is expected —
   "Type something." is the primary path ("rent for September", "keyboard for
   the robot arm", "that was a refund"). Quick-pick options when you're
   confident:

   | Option | Action |
   |--------|--------|
   | Classify → `<suggested account>` | write the suggested income/expense account |
   | Transfer (pair) | it's an inter-account transfer — leave for pair-matching, never classify as income/expense |

   There is **no skip option** — "not sure" is an invitation for a better
   guess + evidence, not a pass.

3. **Write the user's description onto the the accounting backend transaction as a note** —
   via `account.bank.statement.line` `write` with `narration` (= the user's
   words, verbatim), right away when they give it. This is the permanent
   record of WHY it's categorized that way.
4. **Propose the account and CONFIRM before applying.** From the description,
   pick the income/expense account (§cues below) and ask:
   "<description> → <Account name> (<code>) — right?" Options: yes / no, pick
   another / it's a transfer / leave unclassified for now. Only write
   `account_id` (§A.3 — see the the accounting backend 19 caveat there: classify the move's counterpart line, not the statement line) on an explicit yes; never auto-apply a guess.
5. **Business expense (ownership=<business-org>)? → receipt required.** After the
   categorization is confirmed for a business expense, check for the receipt:
   - Look in the business receipts dir configured in the account notes (`.../receipts/<business-org>/YYYY/`) matching
     `YYYY_MM_DD_<amount>_<description>.pdf` (§A.5).
   - If found: **upload/attach it in the accounting backend** to the corresponding `account.move`
     (not the statement line) — via the browser tab or `ir.attachment`.
   - If missing: **ask** — user drops the PDF now (give them the exact target
     filename), or `TaskCreate` a pi-task "Receipt <desc> <date> <amount> →
     attach in the accounting backend" and move on. Importing the expense without a receipt
     plan is not done-done.

Suggested-account cues — income first, then rules, then transfer patterns
(the USER's description always wins over these):

Per-account income/employer account mapping, transfer regexes, minimum
balances, and tax-reminder notes are personal financial data — they live in
`$ORG_CONFIG_DIR/bank-reconciliation-notes.md` (not in this public
skill). Read that file for the account-number → employer map and the
pair-transfer patterns. Unidentified deposit runs: do NOT guess; ask the user.

**Expense rules** (case-insensitive regex on partner_name + payment_ref + name):

| Pattern | Account | Category |
|---------|---------|----------|
| `amazon\|aws` | 6200 | Software & Cloud |
| `google\|gcp` | 6200 | Software & Cloud |
| `uber\|lyft\|taxi` | 6300 | Travel & Transport |
| `restaurant\|cafe\|food` | 6400 | Meals & Entertainment |
| `rent\|lease` | 6100 | Rent & Facilities |
| `salary\|payroll\|wages` | 6000 | Payroll |
| `insurance` | 6500 | Insurance |
| `telephone\|mobile\|tel` | 6250 | Telecom |
| `electricity\|gas\|water` | 6150 | Utilities |
| `interest` | 7000 | Bank Interest |

**Transfer patterns — reconcile as PAIRS, never income/expense:**

Per-bank transfer patterns are in
`$ORG_CONFIG_DIR/bank-reconciliation-notes.md` — reconcile as PAIRS,
never income/expense. Minimum balances come from `bank_accounts.minimum_balance`
(locked capital, not spendable).

If the queue is huge (>50), you may offer to bulk-pre-approve: show the
list of unambiguous, pattern-matched lines WITH their suggested accounts and
get ONE explicit "yes, all of these" from the user before applying them —
still only with approval, never silently.

## 5. Balance check, then cleared

**Before the account is done, the user MUST confirm the the accounting backend balance matches
the bank balance.** Compute both:

- **the accounting backend side:** sum of the journal's statement lines (and/or the journal's
  `current_balance` / last balance field) — from XML-RPC, exact to the penny.
- **Bank side:** the current balance shown on the bank tab (snapshot it) —
  ask the user to read it out if it's buried.

Show both numbers and ask via `ask_user_question`:
"the accounting backend: $X · Bank: $Y — do they match?" Options: yes, they match / no, there's
a difference / there are pending transactions explaining the gap. On "no":
track down the difference (missing txn, import sign error, duplicate,
date-boundary) together, fix it, and re-ask. Only a match (or the user
explicitly accepting a known, explained difference) clears the account.

This is on top of the no-skip rule: every statement line must also be in an
end state (categorized with note / confirmed transfer pair / declared
non-transaction) — an unmatched balance blocks completion just like a
leftover line does.

Then, and ONLY then, write the cursor:

```bash
triage \
  "UPDATE bank_accounts SET last_swept_at='$(date -u +%Y-%m-%dT%H:%M:%SZ)' WHERE id=$ACC_ID;"
```

Report a short wrap-up: every line's end state (categorized / transfer pair /
non-transaction), receipts attached, and the confirmed balance match
(the accounting backend $X = bank $Y). If anything is NOT in an end state or the balance
check failed, do not write the cursor — say what's left and keep the sweep
open. The chief of staff may not move to the next account until this account's
balance check passed.

---

# Appendix — the accounting backend XML-RPC reference

## A.1 Connect

Creds via `source the backend env file (connection URL, database, user, API key)SER`,
`BACKEND_API_KEY`). Helper: `~/.agents/skills/triage_bank_account/scripts/backend_connect.py`.

```python
import sys, os
sys.path.insert(0, os.path.expanduser("~/.agents/skills/triage_bank_account/scripts"))
from backend_connect import connect, search_read, search_count
db, uid, key, models = connect()
```

Security: never echo/log credentials. Verify connection with
`models.execute_kw(db, uid, key, "res.company", "read", [[1]], {"fields": ["name"]})`.

## A.2 Key models

| the accounting backend Model | Purpose |
|---|---|
| `account.journal` | Bank journals (one per bank account) |
| `account.bank.statement.line` | Individual bank transactions |
| `account.move` / `account.move.line` | Journal entries / lines |
| `account.account` | Chart of accounts |
| `res.partner` / `res.partner.bank` | Contacts / bank accounts |
| `account.payment` | Payments |

the accounting backend version caveat: 16+ may push bank data through `account.move.line`; use
`fields_get` to discover available fields if a field is missing:

```python
fields = models.execute_kw(db, uid, key,
    "account.bank.statement.line", "fields_get", [],
    {"attributes": ["string", "type", "required"]})
```

## A.3 Apply a classification (only after user confirmation)

**the accounting backend 19 caveat (learned 2026-09-08, CIBC sweeps):** `account.bank.statement.line`
inherits `account.move` in the accounting backend 19 — there is **no `account_id` field on the
statement line**, and writing one raises an invalid-field error. Classification
happens on the **move's counterpart `account.move.line`**: after the statement
line's move is confirmed, find the move's line whose `account_id` is the
gl-liquidity counterpart (or read the move's `line_ids`) and write the
classification account there. Also in the accounting backend 19 the narration write goes through
the statement line's move (`account.move` `narration`/`ref`) — verify against
existing classified lines on the journal before writing (study how recent
classified lines on this journal look: sign conventions, which line carries the
account). The pre-19 pattern below is kept for reference only:

```python
# Save the user's description as a note on the statement line:
models.execute_kw(db, uid, key, "account.bank.statement.line", "write",
    [[line_id], {"narration": "<user's description, verbatim>"}])

# Pre-the accounting backend-19 pattern (does NOT work on the accounting backend 19 — account_id is not a field
# of account.bank.statement.line there; classify the move's counterpart line
# instead, as described in the caveat above):
acct = search_read(models, db, uid, key,
    "account.account", [["code", "=", suggested_code]], ["id"])
if acct:
    models.execute_kw(db, uid, key,
        "account.bank.statement.line", "write",
        [[line_id], {"account_id": acct[0]["id"]}])
```

Use pagination (limit=500) for any bulk export. XML-RPC timeouts → smaller
pages. `xmlrpc.client.Fault: security` → regenerate the API key
(Settings → Users → Account Security → API Keys) and update `backend.env`.

## A.4 Backup

Download from the accounting backend's own web UI →
Download Backup → save to
`$SYNC_DIR/work/accounting/backend_backup_YYYY-MM-DD.zip`
(browser tab; can be done during any account's sweep when stale >7 days).

## A.5 Business receipts

```
.../receipts/<business-org>/YYYY/YYYY_MM_DD_<amount>_<description>.pdf
```
Exact path lives in the org's secrets repo notes. Attach to the
corresponding `account.move` in the accounting backend (not the statement line) — browser UI.

## A.6 Tax obligations (persist across sweeps — surface as reminders)

- Personal tax items and corporate (business) receipt obligations are listed
  in `$ORG_CONFIG_DIR/bank-reconciliation-notes.md` — surface them as reminders.