CREATE TEMP TABLE rollback_snapshot AS
SELECT a.id AS asset_id,
       a.current_room_id,
       a.location_revision,
       (SELECT count(*) FROM location_audit_events e WHERE e.asset_id = a.id) AS audit_count,
       (SELECT count(*) FROM transfers t WHERE t.asset_id = a.id) AS transfer_count
FROM assets a
WHERE a.asset_tag = 'AST-SYN-002';

BEGIN;
DO $test$
DECLARE
  v_asset uuid;
  v_room uuid;
  v_transfer uuid;
BEGIN
  SELECT id INTO v_asset FROM assets WHERE asset_tag = 'AST-SYN-002';
  SELECT id INTO v_room FROM rooms WHERE code = 'RM-101';
  v_transfer := initiate_transfer(v_asset, v_room);
  IF confirm_transfer(v_transfer) <> 'confirmed' THEN
    RAISE EXCEPTION 'asset_mvp_test: confirm before rollback failed';
  END IF;
  IF (SELECT current_room_id FROM assets WHERE id = v_asset) <> v_room THEN
    RAISE EXCEPTION 'asset_mvp_test: confirm did not move the asset inside the transaction';
  END IF;
END;
$test$;
ROLLBACK;

DO $test$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM rollback_snapshot s
    JOIN assets a ON a.id = s.asset_id
    WHERE a.current_room_id IS DISTINCT FROM s.current_room_id
       OR a.location_revision <> s.location_revision
  ) THEN
    RAISE EXCEPTION 'asset_mvp_test: rollback did not restore custody';
  END IF;
  IF (
    SELECT count(*)
    FROM location_audit_events e
    JOIN rollback_snapshot s ON s.asset_id = e.asset_id
  ) <> (SELECT audit_count FROM rollback_snapshot) THEN
    RAISE EXCEPTION 'asset_mvp_test: rollback did not restore audit rows';
  END IF;
  IF (
    SELECT count(*)
    FROM transfers t
    JOIN rollback_snapshot s ON s.asset_id = t.asset_id
  ) <> (SELECT transfer_count FROM rollback_snapshot) THEN
    RAISE EXCEPTION 'asset_mvp_test: rollback left a transfer row';
  END IF;
END;
$test$;

CREATE FUNCTION test_fail_audit_insert() RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $fn$
BEGIN
  IF current_setting('test.fail_audit', true) = 'on' THEN
    RAISE EXCEPTION 'asset_mvp_test: forced audit failure';
  END IF;
  RETURN NEW;
END;
$fn$;

CREATE TRIGGER test_fail_audit_insert
BEFORE INSERT ON location_audit_events
FOR EACH ROW EXECUTE FUNCTION test_fail_audit_insert();

DO $test$
DECLARE
  v_asset uuid;
  v_room uuid;
  v_from uuid;
  v_revision bigint;
  v_audits bigint;
  v_transfer uuid;
BEGIN
  SELECT id, current_room_id, location_revision
    INTO v_asset, v_from, v_revision
  FROM assets
  WHERE asset_tag = 'AST-SYN-002';
  SELECT count(*) INTO v_audits
  FROM location_audit_events
  WHERE asset_id = v_asset;
  SELECT id INTO v_room FROM rooms WHERE code = 'RM-102';
  v_transfer := initiate_transfer(v_asset, v_room);
  PERFORM set_config('test.fail_audit', 'on', true);

  BEGIN
    PERFORM confirm_transfer(v_transfer);
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%asset_mvp_test: forced audit failure%' THEN
        IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
          RAISE EXCEPTION 'asset_mvp_test: confirm succeeded while audit insert was forced to fail';
        END IF;
        RAISE EXCEPTION 'asset_mvp_test: unexpected forced audit error: %', SQLERRM;
      END IF;
  END;

  IF (SELECT current_room_id FROM assets WHERE id = v_asset) IS DISTINCT FROM v_from
     OR (SELECT location_revision FROM assets WHERE id = v_asset) <> v_revision THEN
    RAISE EXCEPTION 'asset_mvp_test: failed confirm kept a location change';
  END IF;
  IF (SELECT count(*) FROM location_audit_events WHERE asset_id = v_asset) <> v_audits THEN
    RAISE EXCEPTION 'asset_mvp_test: failed confirm kept an audit row';
  END IF;
  IF (SELECT status FROM transfers WHERE id = v_transfer) <> 'initiated' THEN
    RAISE EXCEPTION 'asset_mvp_test: failed confirm kept a terminal transfer status';
  END IF;

  PERFORM set_config('test.fail_audit', 'off', true);
  IF confirm_transfer(v_transfer) <> 'confirmed' THEN
    RAISE EXCEPTION 'asset_mvp_test: confirm after a forced audit failure did not succeed';
  END IF;
  IF NOT location_audit_is_consistent() THEN
    RAISE EXCEPTION 'asset_mvp_test: audit inconsistent after recovery confirm';
  END IF;
END;
$test$;

DO $test$
DECLARE
  v_room uuid;
BEGIN
  SELECT id INTO v_room FROM rooms WHERE code = 'RM-101';
  PERFORM set_config('test.fail_audit', 'on', true);
  BEGIN
    PERFORM register_asset('AST-SYN-005', 'Synthetic stool', v_room);
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%asset_mvp_test: forced audit failure%' THEN
        IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
          RAISE EXCEPTION 'asset_mvp_test: asset insert succeeded without an audit row';
        END IF;
        RAISE EXCEPTION 'asset_mvp_test: unexpected registration failure: %', SQLERRM;
      END IF;
  END;
  IF EXISTS (SELECT 1 FROM assets WHERE asset_tag = 'AST-SYN-005') THEN
    RAISE EXCEPTION 'asset_mvp_test: asset row persisted after audit failure';
  END IF;
  IF NOT location_audit_is_consistent() THEN
    RAISE EXCEPTION 'asset_mvp_test: audit inconsistent after failed registration';
  END IF;
END;
$test$;
