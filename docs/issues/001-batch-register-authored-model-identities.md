# Batch-register authored model identities

Status: not started. This file is a draft. It is not a filed issue.

## Scope

Add one forward SQL migration, `db/migrations/002_import_batch.sql`, and tests that `db/tests/run.sh` picks up.

Add a staging table `model_import_rows` for one model version. Each row is a candidate authored identifier: stable id text, stable id kind, and object role. Add `commit_import_batch(model_version_id)` that processes the pending rows of that version.

For each row, independently:

- Call the same rules as `register_model_object`.
- A blank, untrimmed, over-long, bare-integer, or malformed IFC value becomes a review and does not insert a `model_objects` row.
- A duplicate authored id becomes a `duplicate_stable_id` review and does not change the existing object or any mapping.
- A well-formed new id inserts one `model_objects` row and no mapping.
- A kind that does not match the model version's `source_kind` is a row outcome, not a reason to abort the rows that already succeeded.

The batch must not update `assets.current_room_id`, must not insert `transfers`, and must not accept a mapping.

Do not replace `001_initial.sql` functions. Do not add a web server, a frontend, a file parser, or a Three.js dependency.

## Out of scope

- Reading `.gltf`, `.glb`, or `.ifc` bytes. The caller has already extracted candidate strings.
- Inventing an extras field name. The staging row already carries the string.
- Copying mappings from an older model version.
- Issue 004.

## Acceptance criteria

1. Load three synthetic staging rows into a fresh database that already has `syn-gltf-v1` from the fixture: one new extras id `syn.asset.batch`, one repeat of `syn.asset.cabinet`, and one bare integer `4`. After `commit_import_batch`, the result counts are 1 registered, 1 duplicate review, and 1 rejected-unstable review.
2. `model_objects` gains only `syn.asset.batch`. The cabinet object's `stable_id` is still `syn.asset.cabinet`, and its accepted mapping still points at `AST-SYN-001`.
3. No staging row changes `AST-SYN-001.current_room_id` or `AST-SYN-002.current_room_id`.
4. A second call with no new pending rows does not insert another cabinet object or another duplicate review for the same staging row.
5. If one staged IFC id is applied to the glTF version, that row is recorded as a kind mismatch and the other rows in the same batch still follow criteria 1–3.
6. `information_schema.columns` still has no `three_uuid`, `runtime_uuid`, `node_index`, or `object3d_uuid` column.
7. `./db/tests/run.sh` passes, including the new tests. If PostgreSQL cannot be reached, stop. Do not delete a criterion to make the run green.

## Note on what is already enforced

Unique `(model_version_id, stable_id_kind, stable_id)` already rejects a second object. The batch function has to turn that into a review without rolling back earlier rows in the same call. That isolation is not provided by `register_model_object`, which is one call and one transaction outcome.
