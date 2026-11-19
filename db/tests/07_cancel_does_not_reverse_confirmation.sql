DO $test$
DECLARE
  v_asset uuid;
  v_start uuid;
  v_revision bigint;
  v_room_101 uuid;
  v_room_102 uuid;
  v_cancel uuid;
  v_keep uuid;
  v_audits bigint;
BEGIN
  SELECT id, current_room_id, location_revision
    INTO v_asset, v_start, v_revision
  FROM assets
  WHERE asset_tag = 'AST-SYN-002';
  SELECT id INTO v_room_101 FROM rooms WHERE code = 'RM-101';
  SELECT id INTO v_room_102 FROM rooms WHERE code = 'RM-102';

  v_cancel := initiate_transfer(v_asset, v_room_101);
  v_keep := initiate_transfer(v_asset, v_room_102);

  IF cancel_transfer(v_cancel) <> 'cancelled' THEN
    RAISE EXCEPTION 'asset_mvp_test: cancel failed';
  END IF;
  IF cancel_transfer(v_cancel) <> 'already_cancelled' THEN
    RAISE EXCEPTION 'asset_mvp_test: second cancel was not idempotent';
  END IF;
  IF confirm_transfer(v_cancel) <> 'cancelled' THEN
    RAISE EXCEPTION 'asset_mvp_test: cancelled transfer was confirmed';
  END IF;
  IF (SELECT current_room_id FROM assets WHERE id = v_asset) IS DISTINCT FROM v_start THEN
    RAISE EXCEPTION 'asset_mvp_test: cancel moved the asset';
  END IF;

  IF confirm_transfer(v_keep) <> 'confirmed' THEN
    RAISE EXCEPTION 'asset_mvp_test: remaining transfer did not confirm';
  END IF;
  SELECT count(*) INTO v_audits
  FROM location_audit_events
  WHERE transfer_id = v_keep;
  IF cancel_transfer(v_keep) <> 'confirmed_irreversible' THEN
    RAISE EXCEPTION 'asset_mvp_test: cancel reversed or hid a confirmed transfer';
  END IF;
  IF (SELECT status FROM transfers WHERE id = v_keep) <> 'confirmed' THEN
    RAISE EXCEPTION 'asset_mvp_test: confirmed status was cleared';
  END IF;
  IF (SELECT current_room_id FROM assets WHERE id = v_asset) <> v_room_102 THEN
    RAISE EXCEPTION 'asset_mvp_test: irreversible cancel changed the room';
  END IF;
  IF (SELECT location_revision FROM assets WHERE id = v_asset) <> v_revision + 1 THEN
    RAISE EXCEPTION 'asset_mvp_test: irreversible cancel changed the revision';
  END IF;
  IF (SELECT count(*) FROM location_audit_events WHERE transfer_id = v_keep) <> v_audits THEN
    RAISE EXCEPTION 'asset_mvp_test: irreversible cancel changed audit history';
  END IF;
  IF EXISTS (SELECT 1 FROM location_audit_events WHERE transfer_id = v_cancel) THEN
    RAISE EXCEPTION 'asset_mvp_test: cancelled transfer has an audit row';
  END IF;
  IF NOT location_audit_is_consistent() THEN
    RAISE EXCEPTION 'asset_mvp_test: cancel checks left the audit inconsistent';
  END IF;
END;
$test$;
