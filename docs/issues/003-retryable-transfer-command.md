# Retryable transfer command

Status: not started. This file is a draft. It is not a filed issue.

## Scope

Add one executable script, `db/bin/transfer.sh`, that connects to a database the operator names and calls the existing SQL functions. Subcommands:

- `initiate <asset_tag> <to_room_code>` prints the new transfer UUID.
- `confirm <transfer_uuid>` prints the `confirm_transfer` result code.
- `cancel <transfer_uuid>` prints the `cancel_transfer` result code.

Exit codes:

| Code | When |
| --- | --- |
| 0 | Initiate succeeded. Confirm returned `confirmed` or `already_confirmed`. Cancel returned `cancelled` or `already_cancelled`. |
| 3 | Confirm returned `conflict` or `already_conflict`. |
| 4 | Confirm returned `cancelled`. Cancel returned `confirmed_irreversible` or `conflict_terminal`. |
| 2 | `not_found`, unknown tag, or unknown room. |
| 1 | Usage or connection error. |

Confirming the same UUID twice is success both times. The second run must not add an audit row. The script must not open a listening port and must not embed a database password.

## Out of scope

- An HTTP API or a web page.
- Choosing a frontend framework.
- Replacing `confirm_transfer`.
- Automatic detection of physical movement.

## Acceptance criteria

1. Against a fresh fixture database, initiating `AST-SYN-002` to `RM-101` prints a UUID and leaves the cart in `RM-201`.
2. Confirming that UUID prints `confirmed`, moves the cart to `RM-101`, and writes one audit row. Confirming it again prints `already_confirmed`, exit 0, and still one audit row.
3. A second initiated transfer for the same cart, confirmed after the first, prints `conflict`, exits 3, and does not add an audit row.
4. Cancelling the confirmed transfer prints `confirmed_irreversible`, exits 4, and leaves the room and the audit row in place.
5. Shell checks cover those four results and are runnable without a browser.
6. The script contains no password, token, or personal name.

## Already implemented

The result codes and the transaction behavior already come from SQL. This draft is only the command boundary.
