# Usage-control plan

This plan limits later agent sessions. It does not reserve credits, promise reimbursement, or start a session. A person sets the product's spending cap before pasting `docs/devin-session-prompt.md`. If the product does not show a cap, do not start an unattended session.

## One session, one draft

| Order | Draft | Session rule |
| --- | --- | --- |
| 1 | 001 batch registration | Only this draft is in the prepared prompt |
| 2 | 005 least-privilege role | A later session, and only after a person accepts the 001 diff |
| 3 | 002 finish-import reviews | After 001, because it assumes registered objects |
| 4 | 003 transfer command | Independent of the view; still its own session |
| 5 | 004 read-only view | Not part of an unattended session. A person asks for it in writing first |

Do not run two of these at once. Do not let a session "continue into the viewer" because the database tests passed.

## Stop conditions

Stop the session, and do not resume it, if it:

- adds `package.json`, a React app, Three.js, a dev server, or a container for deployment
- edits `001_initial.sql` instead of adding a forward migration
- deletes or relaxes an invariant test
- creates a hosted issue, pull request, or public repository
- introduces a password, token, real person, or customer name
- reports success without a `./db/tests/run.sh` summary, unless it clearly says PostgreSQL was unreachable and stops

A failed test is a stop for review, not a reason to widen the task.

## What the person does

1. Read the draft issue and the prompt.
2. Set the spending cap in the vendor UI.
3. Paste the prompt into one session.
4. Read the diff and the test summary.
5. Decide whether another draft is worth another capped session.

This repository is a local draft until that person publishes it. Preparing these files is not that publication.

## What not to spend a session on

- Rebuilding `confirm_transfer`, the audit table, or the mapping triggers.
- A login system. The draft has no people.
- Loading real building models or real names.
- Claiming the result satisfies a vendor checklist. The vendor decides that.
