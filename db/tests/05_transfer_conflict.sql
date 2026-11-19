DO $test$
DECLARE
  v_asset uuid;
  v_start uuid;
  v_revision bigint;
  v_room_101 uuid;
  v_room_102 uuid;
  v_first uuid;
  v_second uuid;
BEGIN
  SELECT id, current_room_id, location_revision
    INTO v_asset, v_start, v_revision
  FROM assets
  WHERE asset_tag = 'AST-SYN-002';
  SELECT id INTO v_room_101 FROM rooms WHERE code = 'RM-101';
  SELECT id INTO v_room_102 FROM rooms WHERE code = 'RM-102';

  v_first := initiate_transfer(v_asset, v_room_101);
  v_second := initiate_transfer(v_asset, v_room_102);

  IF (SELECT expected_location_revision FROM transfers WHERE id = v_first)
     <> (SELECT expected_location_revision FROM transfers WHERE id = v_second) THEN
    RAISE EXCEPTION 'asset_mvp_test: concurrent initiates did not capture the same revision';
  END IF;
  IF (SELECT current_room_id FROM assets WHERE id = v_asset) IS DISTINCT FROM v_start THEN
    RAISE EXCEPTION 'asset_mvp_test: two initiates moved the asset';
  END IF;

  IF confirm_transfer(v_first) <> 'confirmed' THEN
    RAISE EXCEPTION 'asset_mvp_test: first confirm should win';
  END IF;
  IF confirm_transfer(v_second) <> 'conflict' THEN
    RAISE EXCEPTION 'asset_mvp_test: second confirm should conflict';
  END IF;
  IF confirm_transfer(v_second) <> 'already_conflict' THEN
    RAISE EXCEPTION 'asset_mvp_test: repeat conflict confirm was not stable';
  END IF;

  IF (SELECT current_room_id FROM assets WHERE id = v_asset) <> v_room_101 THEN
    RAISE EXCEPTION 'asset_mvp_test: conflict changed or lost the winning room';
  END IF;
  IF (SELECT location_revision FROM assets WHERE id = v_asset) <> v_revision + 1 THEN
    RAISE EXCEPTION 'asset_mvp_test: conflict incremented the revision';
  END IF;
  IF (SELECT status FROM transfers WHERE id = v_second) <> 'conflict' THEN
    RAISE EXCEPTION 'asset_mvp_test: losing transfer was not marked conflict';
  END IF;
  IF EXISTS (SELECT 1 FROM location_audit_events WHERE transfer_id = v_second) THEN
    RAISE EXCEPTION 'asset_mvp_test: conflict wrote an audit row';
  END IF;
  IF (SELECT count(*) FROM location_audit_events WHERE transfer_id = v_first) <> 1 THEN
    RAISE EXCEPTION 'asset_mvp_test: winner does not have one audit row';
  END IF;
  IF NOT location_audit_is_consistent() THEN
    RAISE EXCEPTION 'asset_mvp_test: conflict left the audit inconsistent';
  END IF;
END;
$test$;
