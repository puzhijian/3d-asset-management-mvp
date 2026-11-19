DO $test$
DECLARE
  v_asset uuid;
  v_room uuid;
  v_other uuid;
  v_revision bigint;
  v_name text;
BEGIN
  SELECT id, current_room_id, location_revision, name
    INTO v_asset, v_room, v_revision, v_name
  FROM assets
  WHERE asset_tag = 'AST-SYN-002';
  SELECT id INTO v_other FROM rooms WHERE code = 'RM-102';

  BEGIN
    UPDATE assets SET asset_tag = 'AST-SYN-999' WHERE id = v_asset;
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%asset_mvp: asset id and asset_tag are immutable%' THEN
        IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
          RAISE EXCEPTION 'asset_mvp_test: asset tag was changed';
        END IF;
        RAISE EXCEPTION 'asset_mvp_test: unexpected tag error: %', SQLERRM;
      END IF;
  END;

  BEGIN
    UPDATE assets SET id = gen_random_uuid() WHERE id = v_asset;
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%asset_mvp: asset id and asset_tag are immutable%'
         AND SQLERRM NOT LIKE '%violates foreign key constraint%' THEN
        IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
          RAISE EXCEPTION 'asset_mvp_test: asset id was changed';
        END IF;
        RAISE EXCEPTION 'asset_mvp_test: unexpected id error: %', SQLERRM;
      END IF;
  END;

  UPDATE assets SET name = 'Synthetic cart renamed' WHERE id = v_asset;
  IF (SELECT asset_tag FROM assets WHERE id = v_asset) <> 'AST-SYN-002' THEN
    RAISE EXCEPTION 'asset_mvp_test: rename changed the custody tag';
  END IF;
  UPDATE assets SET name = v_name WHERE id = v_asset;

  BEGIN
    UPDATE assets
       SET current_room_id = v_other,
           location_revision = v_revision + 1
     WHERE id = v_asset;
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%asset_mvp: asset location changes only through confirm_transfer%' THEN
        IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
          RAISE EXCEPTION 'asset_mvp_test: raw location update succeeded';
        END IF;
        RAISE EXCEPTION 'asset_mvp_test: unexpected location error: %', SQLERRM;
      END IF;
  END;

  BEGIN
    INSERT INTO assets (asset_tag, name, current_room_id, location_revision)
    VALUES ('AST-SYN-009', 'Synthetic bad revision', v_room, 5);
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%asset_mvp: new assets start at location_revision 1%' THEN
        IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
          RAISE EXCEPTION 'asset_mvp_test: non-1 initial revision was stored';
        END IF;
        RAISE EXCEPTION 'asset_mvp_test: unexpected revision error: %', SQLERRM;
      END IF;
  END;

  PERFORM register_asset('AST-SYN-003', 'Synthetic stool', NULL);
  IF (SELECT location_revision FROM assets WHERE asset_tag = 'AST-SYN-003') <> 1 THEN
    RAISE EXCEPTION 'asset_mvp_test: unplaced asset revision';
  END IF;
  IF (SELECT event_type FROM location_audit_events e
      JOIN assets a ON a.id = e.asset_id
      WHERE a.asset_tag = 'AST-SYN-003') <> 'registered_unplaced' THEN
    RAISE EXCEPTION 'asset_mvp_test: unplaced registration audit missing';
  END IF;

  IF (SELECT current_room_id FROM assets WHERE id = v_asset) IS DISTINCT FROM v_room
     OR (SELECT location_revision FROM assets WHERE id = v_asset) <> v_revision THEN
    RAISE EXCEPTION 'asset_mvp_test: failed writes changed custody';
  END IF;
  IF NOT location_audit_is_consistent() THEN
    RAISE EXCEPTION 'asset_mvp_test: identity checks left the audit inconsistent';
  END IF;
END;
$test$;

-- Known gap, measured in two parts:
-- 1. Setting app.write_path lets the table owner update the room inside a
--    transaction without confirm_transfer.
-- 2. Committing that change without a matching audit row is rejected.
-- A forged move that also writes a matching transfer and audit is not blocked
-- by this check. That remaining privilege gap is not closed in this starter.
\set ON_ERROR_STOP off
BEGIN;
DO $test$
DECLARE
  v_asset uuid;
  v_other uuid;
  v_revision bigint;
BEGIN
  SELECT id, location_revision
    INTO v_asset, v_revision
  FROM assets
  WHERE asset_tag = 'AST-SYN-002';
  SELECT id INTO v_other FROM rooms WHERE code = 'RM-102';
  PERFORM set_config('app.write_path', 'confirm_transfer', true);
  UPDATE assets
     SET current_room_id = v_other,
         location_revision = v_revision + 1
   WHERE id = v_asset;
  IF (SELECT current_room_id FROM assets WHERE id = v_asset) <> v_other THEN
    RAISE EXCEPTION 'asset_mvp_test: GUC bypass did not update the row inside the transaction';
  END IF;
  IF location_audit_is_consistent() THEN
    RAISE EXCEPTION 'asset_mvp_test: GUC bypass unexpectedly kept the audit consistent';
  END IF;
END;
$test$;
\echo EXPECTED_REJECT: inconsistent location and audit must not commit
COMMIT;
\set ON_ERROR_STOP on

DO $test$
BEGIN
  IF (SELECT r.code
      FROM assets a
      JOIN rooms r ON r.id = a.current_room_id
      WHERE a.asset_tag = 'AST-SYN-002') <> 'RM-201' THEN
    RAISE EXCEPTION 'asset_mvp_test: inconsistent GUC bypass was committed';
  END IF;
  IF (SELECT location_revision FROM assets WHERE asset_tag = 'AST-SYN-002') <> 1 THEN
    RAISE EXCEPTION 'asset_mvp_test: inconsistent GUC bypass kept a revision change';
  END IF;
  IF NOT location_audit_is_consistent() THEN
    RAISE EXCEPTION 'asset_mvp_test: audit inconsistent after rejected GUC commit';
  END IF;
END;
$test$;
