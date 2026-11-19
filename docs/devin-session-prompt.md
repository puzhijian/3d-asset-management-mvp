# Devin session prompt

Paste the block below only if a person has decided to spend a session on draft issue 001. This file does not start a session, does not grant credits, and does not make any program accept the project.

The prompt is one issue. It is not permission to build the MVP.

```text
You are working in a private database starter for a proposed 3D asset
management MVP. It is not an application. Do not claim that the MVP is
implemented, that a 3D demo works, or that any credit or grant program
will accept this repository.

Implement only docs/issues/001-batch-register-authored-model-identities.md.
Follow its acceptance criteria literally. Add db/migrations/002_import_batch.sql
and SQL tests under db/tests/. Run ./db/tests/run.sh and leave the output in
your final note. If PostgreSQL is not reachable, stop and say the tests were
not run. Do not delete or weaken an existing test to get a green run.

Use the existing register_model_object rules. A bad staging row must not roll
back earlier successful rows in that batch, and must not change an existing
model object, an accepted mapping, or any asset's current room.

Do not add a frontend, React, Three.js, a web server, Docker, a hosted
database, or a deployment. Do not parse glTF or IFC files. Do not create
GitHub issues, pull requests, or public posts. Do not invent users, customers,
passwords, or tokens. Use only clearly synthetic fixture labels.

Do not start issues 002, 003, 004, or 005. Issue 004 is a view and is out of
bounds for this session even if the batch work finishes early.

Stop when the new tests pass, or when you are blocked. Summarize files
changed, tests passed, and tests not run. Do not continue into a viewer.
```

Before pasting, set a spending cap in the product's own controls. This repository cannot set or see that cap. After the session, a person reviews the diff before any further session.
