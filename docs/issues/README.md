# Draft issues

These files are not tracker issues. They have not been filed on GitHub or anywhere else. They are acceptance-criteria drafts for later work. The schema starter does not implement them.

Do not start a session from more than one file at a time. `docs/devin-session-prompt.md` authorizes draft 001 only.

| Draft | Title | Already in the database starter | Still not built |
| --- | --- | --- | --- |
| [001](001-batch-register-authored-model-identities.md) | Batch-register authored model identities | Single-row `register_model_object` | A staging table and a batch function that keeps going row by row |
| [002](002-record-room-mismatches-without-moving-assets.md) | Record room mismatches without moving assets | Single-call review functions | A finish-import report that opens the reviews a file actually requires |
| [003](003-retryable-transfer-command.md) | Retryable transfer command | `initiate_transfer` and `confirm_transfer` | A small command wrapper and exit codes |
| [004](004-read-only-spatial-view.md) | Read-only spatial view | Nothing visual | A later React/Three.js view, only after a person asks for it |
| [005](005-least-privilege-database-role.md) | Least-privilege database role | Triggers and a GUC write gate | A non-owner role that cannot forge a consistent move |
