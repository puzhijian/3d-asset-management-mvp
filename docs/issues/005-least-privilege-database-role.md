# Least-privilege database role

Status: not started. This file is a draft. It is not a filed issue.

## Scope

Add a migration that creates a non-superuser role `asset_mvp_app` with no password stored in the repository. The test script may create the role in the throwaway database and set a password only in that local process.

The role may execute the custody and registration functions. It may not `UPDATE` or `DELETE` `assets`, `transfers`, or `location_audit_events` directly. Those functions run as a definer that is not the app role, so `confirm_transfer` still works.

Setting `app.write_path` from the app role must not be enough to change `current_room_id`, because the role has no table update privilege.

## Out of scope

- A production secret manager.
- Row-level security per person. This starter has no people.
- Rewriting the transfer state machine.

## Acceptance criteria

1. As `asset_mvp_app`, `confirm_transfer` on a new initiated fixture transfer returns `confirmed`, the room changes, and exactly one new audit row exists.
2. As `asset_mvp_app`, a direct `UPDATE` of `assets.current_room_id` fails even after `set_config('app.write_path', 'confirm_transfer', true)`.
3. As `asset_mvp_app`, `UPDATE` and `DELETE` on `location_audit_events` fail.
4. As `asset_mvp_app`, `register_model_object` for a duplicate extras id inserts a review and does not change the existing object's mapping.
5. The repository contains no password literal. The test harness generates a local password or uses peer authentication.
6. `./db/tests/run.sh` passes with these checks included.

## Already implemented

Triggers and the deferred consistency check already exist. They are not a substitute for this role. The owner can still write a consistent forged move today. This draft is done only when criterion 2 passes.
