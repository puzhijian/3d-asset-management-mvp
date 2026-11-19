# 3D asset management MVP — planning and database starter

**Status: this is not an application.** It is a private planning draft plus an initial PostgreSQL schema, synthetic fixtures, and database tests. Nothing here is deployed, published as a product, or filed as a tracker issue.

This repository does not make a system eligible for any credit, grant, or vendor program. It does not implement a React application, a Three.js viewer, a glTF parser, an IFC parser, authentication, or a running API.

The proposed later stack is React, TypeScript, Three.js, and PostgreSQL. Only the PostgreSQL starter is in this repository.

## What the starter records

Custody and rendering are different identities.

- An asset has a database UUID and an immutable custody tag. Those values are assigned here. They are not a Three.js runtime UUID, a scene-graph node index, or an IFC GlobalId.
- A model object, inside one immutable model version, is identified by an authored glTF `extras` id or an IFC GlobalId.
- A mapping says which authored object corresponds to which asset or room. Accepting a mapping does not change the asset's current room.
- The current room changes only when a transfer is confirmed, or when the asset is first registered. The database does not watch a viewport, a file, or a scanner.

Physical movement is not detected. A scan, an audit, or a manual observation has to be entered. If that observation disagrees with the custody room, the starter stores a review and leaves the room where it is.

## Narrow MVP this draft is aimed at

In scope for the product being planned:

1. Buildings, rooms, and assets with a current custody room.
2. Transfers that are initiated, then confirmed. Confirmation updates the room and appends one audit event in the same transaction. A second confirmation does not move the asset again. A conflicting transfer does not move it either.
3. Versioned links from those records to authored glTF `extras` ids and IFC GlobalIds.
4. A review when an identifier is missing, duplicated, unstable, or when a model room and a database room disagree. No silent reassignment.

Out of scope for this draft, and not started:

- A user interface, including any Three.js scene.
- Reading `.gltf`, `.glb`, or `.ifc` bytes.
- Accounts, passwords, and production roles. The schema's write gate is not a privilege boundary; see below.
- Inferring that an object moved because a mesh, camera, or runtime id changed.
- Publishing this draft or opening tracker issues. The Markdown files under `docs/issues/` are drafts only.

## What the database enforces now

These are enforced by constraints, triggers, and SQL functions in `db/migrations/001_initial.sql`:

| Rule | Enforcement |
| --- | --- |
| Asset `id` and `asset_tag` do not change | Trigger |
| A new asset starts at location revision 1 and gets one registration audit row | Trigger |
| Later room changes go through `confirm_transfer` | Trigger plus the `app.write_path` setting |
| Confirmation is one transaction: transfer status, room, revision, and one audit row | `confirm_transfer` |
| Confirming the same transfer again does not write a second move | Status check, plus a unique audit index |
| A second initiated transfer loses if the room or revision changed | `confirm_transfer` returns `conflict` and writes no audit row |
| Cancelling a confirmed transfer does not reverse it or delete history | `cancel_transfer` |
| Audit rows cannot be updated or deleted | Trigger, including when `app.write_path` is set |
| An inconsistent room/audit pair cannot be committed | Deferred constraint trigger |
| Rooms belong to buildings; referenced rows cannot be deleted | Foreign keys |
| Model versions and authored ids are immutable | Triggers |
| The same authored id cannot be stored twice in one model version | Unique constraint |
| glTF versions store `gltf_extras`; IFC versions store `ifc_global_id` | Trigger |
| IFC GlobalIds stored as identities are 22 characters from the IFC alphabet | Check constraint |
| Bare integer glTF ids are not stored as identities | Check constraint and `register_model_object` |
| A room mapping cannot be accepted across buildings | Trigger; the function records a review instead |
| Accepted mappings are not retargeted in place | Trigger |
| Resolving a review does not create a mapping or move an asset | No such write exists; subject columns are immutable |

`confirm_transfer` result codes are `confirmed`, `already_confirmed`, `conflict`, `already_conflict`, `cancelled`, and `not_found`.

## What is proposed application behavior, not enforced here

- Choosing a glTF `extras` field or an IFC property while parsing a file. The schema cannot see file bytes.
- Refusing a Three.js `Object3D.uuid` when that uuid was copied into glTF `extras`. A UUID-shaped extras value is a legal authored id. The database cannot tell who minted it. The tests record this limit instead of pretending to close it.
- Deciding that geometry inside a model room disagrees with custody. There is no coordinate check. `flag_custody_room_mismatch` only stores an observation that the caller already made.
- Opening a review for every unmatched object after a batch import. `open_unmatched_object_review` does it for one object when called. It is not an importer.
- Per-row commit behavior for a whole file of identifiers. One call is atomic. A batch that keeps going after a bad row is issue 001 and is not implemented.
- A non-owner database role that cannot set `app.write_path` and forge a consistent move. Issue 005. Not implemented.
- Any screen, command-line wrapper, or HTTP route. Issues 003 and 004. Not implemented.

## Local database check

Requires PostgreSQL 14 or newer, already running, and permission to create a database. The script drops and recreates only the database named `asset_mvp_starter_test`.

```bash
chmod +x db/tests/run.sh
./db/tests/run.sh
```

The script prints `PASS` or `FAIL` per file, then a `SUMMARY` line. It does not install packages, open a port, or load a frontend.

On PostgreSQL 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1), one run of this script after the starter was written produced `sql_passed=10 sql_failed=0 concurrent_passed=2 concurrent_failed=0`. During `03_immutable_identity_and_location_gate.sql`, psql prints `ERROR: asset_mvp: location audit is inconsistent at commit`. That error is the rejected commit of a room change with no matching audit row. The file is still a pass if the following checks show the room unchanged. No other major version was run. The script's final `NOT IN THIS RUN` line is the list of checks this repository does not perform.

Apply the starter by hand to some other new database with:

```bash
psql -d YOUR_NEW_DATABASE -v ON_ERROR_STOP=1 -f db/migrations/001_initial.sql
psql -d YOUR_NEW_DATABASE -v ON_ERROR_STOP=1 -f db/fixtures/synthetic.sql
```

The fixture file is for an empty database. Running it twice fails on purpose. The rows are synthetic labels such as `Synthetic cabinet` and `BLD-NORTH`. They are not people, customers, or real sites.

## Layout

| Path | Contents |
| --- | --- |
| `db/migrations/001_initial.sql` | Schema, triggers, and functions |
| `db/fixtures/synthetic.sql` | Synthetic buildings, assets, model links, and one confirmed transfer |
| `db/tests/run.sh` | Creates `asset_mvp_starter_test` and runs the checks |
| `db/tests/*.sql` | Single-session invariant checks |
| `docs/architecture.md` | Custody, transfers, model identity, and limits |
| `docs/issues/` | Draft issues with acceptance criteria. Not filed anywhere |
| `docs/devin-session-prompt.md` | One future session, limited to draft issue 001 |
| `docs/usage-control-plan.md` | How to keep that kind of session small |
| `docs/zh-guide.md` | Short Chinese guide. The English documents are the source of truth |

## Limits of this draft

- One migration file. No migration tool, no upgrade path, no roles, no row-level security.
- `app.write_path` is a session setting. Combined with table ownership, it does not stop a forged but consistent move. The commit trigger stops inconsistent room/audit pairs only.
- The commit trigger reads the custody tables once per changed row. That is acceptable for this starter and a poor fit for a large production table.
- `SET CONSTRAINTS ALL IMMEDIATE` is not a supported way to call `confirm_transfer`.
- No binary models are stored. Model versions are labels only.
- Tests that have been run are the ones `db/tests/run.sh` executes on a machine where PostgreSQL is reachable. Parser, browser, and privilege-role behavior are not covered, because those programs are not in the repository.
- Eligibility for an external program is a decision by that program. These files do not establish it.

## Private draft

Do not treat this working copy as a public repository. Do not create hosted issues from `docs/issues/` unless a person chooses to publish later and reviews the text first. A short Chinese reading guide is in `docs/zh-guide.md`.
