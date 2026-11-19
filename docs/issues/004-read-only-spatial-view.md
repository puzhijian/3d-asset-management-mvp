# Read-only spatial view

Status: not started. This file is a draft. It is not a filed issue.

Do not implement this in the same session as another draft. Do not start it until a person explicitly asks for a view. The database starter is intentionally without a frontend.

## Scope

A later React and TypeScript page may load one already-extracted scene and draw asset markers from accepted `asset_model_mappings` only. The page reads. It does not initiate transfers, confirm transfers, accept mappings, or resolve reviews.

Identity in the view is the authored `stable_id` joined through the database. It is not `Object3D.uuid` and it is not a node index.

## Out of scope

- Writing custody from a click, a drag, or a camera move.
- Treating a change in a runtime UUID as a move.
- Parsing IFC in the browser as part of the first slice.
- Accounts and deployment.

## Acceptance criteria

1. With the fixture mapping loaded, the page shows a marker for `syn.asset.cabinet` and no marker for `syn.asset.unmatched`.
2. The cabinet marker's key equals `syn.asset.cabinet`, and a test or inspection shows it does not read `object.uuid` as that key.
3. Loading the page does not change `assets.current_room_id` or insert a `transfers` row.
4. The page states, in its own UI copy, that the picture is not a live location and that a move requires a recorded transfer.
5. Desktop and a narrow viewport both show the marker and that sentence without overlapping into unreadability.

## Not enforceable in the current database

The schema can refuse bad stored ids. It cannot inspect a future JavaScript bundle. These criteria need a view that does not exist yet, so they are unchecked.
