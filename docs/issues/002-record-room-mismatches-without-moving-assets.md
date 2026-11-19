# Record room mismatches without moving assets

Status: not started. This file is a draft. It is not a filed issue.

## Scope

Add a SQL function `finish_model_import(model_version_id)` and tests.

After objects for a model version have been registered, the function:

- Opens one `unmatched_model_object` review for each object in that version that has no accepted asset mapping and no accepted room mapping, using the existing `open_unmatched_object_review` behavior so a second call is idempotent.
- Does not open that review for an object that already has an accepted mapping.
- Accepts a set of synthetic observations `(asset_tag, observed_room_code)` and calls the existing custody rule: a differing room becomes one `custody_room_mismatch` review, and a matching room does not.
- Does not insert a transfer, does not change `current_room_id`, and does not modify an accepted mapping.

The observations are arguments to the function. The function does not read geometry.

## Out of scope

- Parsing files or computing which mesh is inside which room.
- Resolving a review by choosing a new asset. Resolution may set status to `resolved` and must still not move custody.
- A user interface.
- Silent replacement of `syn.room.101`'s accepted room.

## Acceptance criteria

1. On the fixture data, `finish_model_import` for `syn-gltf-v1` opens exactly one unmatched review, for `syn.asset.unmatched`. A second call returns the same open review and does not insert another.
2. `syn.asset.cabinet` and `syn.room.101` do not gain an unmatched review.
3. An observation that `AST-SYN-001` was seen in `RM-101` inserts one `custody_room_mismatch` review. The cabinet's current room remains `RM-102`. Transfer count for that asset does not change.
4. An observation that `AST-SYN-001` was seen in `RM-102` inserts no review.
5. Setting the new mismatch review to `resolved` leaves the cabinet in `RM-102`.
6. A proposed room link from the north model object `syn.room.101` to `RM-201` still creates no `room_model_mappings` row.
7. `./db/tests/run.sh` passes with the new tests included.

## Already implemented

`propose_room_mapping`, `flag_custody_room_mismatch`, and `open_unmatched_object_review` already exist for one call. This draft is the batch finish step, not a rewrite of those functions.
