DO $test$
DECLARE
  v_asset uuid;
  v_from uuid;
  v_to uuid;
  v_transfer uuid;
  v_revision bigint;
  v_unplaced uuid;
  v_room uuid;
  v_second uuid;
BEGIN
  SELECT id, current_room_id, location_revision
    INTO v_asset, v_from, v_revision
  FROM assets
  WHERE asset_tag = 'AST-SYN-002';
  SELECT id INTO v_to FROM rooms WHERE code = 'RM-102';

  BEGIN
    PERFORM initiate_transfer(v_asset, v_from);
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%asset_mvp: same_room%' THEN
        IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
          RAISE EXCEPTION 'asset_mvp_test: same-room transfer was created';
        END IF;
        RAISE EXCEPTION 'asset_mvp_test: unexpected same-room error: %', SQLERRM;
      END IF;
  END;

  v_transfer := initiate_transfer(v_asset, v_to);
  IF (SELECT status FROM transfers WHERE id = v_transfer) <> 'initiated' THEN
    RAISE EXCEPTION 'asset_mvp_test: transfer did not start as initiated';
  END IF;
  IF (SELECT current_room_id FROM assets WHERE id = v_asset) IS DISTINCT FROM v_from THEN
    RAISE EXCEPTION 'asset_mvp_test: initiate moved the asset';
  END IF;

  IF confirm_transfer(v_transfer) <> 'confirmed' THEN
    RAISE EXCEPTION 'asset_mvp_test: first confirm failed';
  END IF;
  IF confirm_transfer(v_transfer) <> 'already_confirmed' THEN
    RAISE EXCEPTION 'asset_mvp_test: duplicate confirm was not idempotent';
  END IF;
  IF confirm_transfer(v_transfer) <> 'already_confirmed' THEN
    RAISE EXCEPTION 'asset_mvp_test: third confirm was not idempotent';
  END IF;
  IF confirm_transfer(gen_random_uuid()) <> 'not_found' THEN
    RAISE EXCEPTION 'asset_mvp_test: unknown transfer was not not_found';
  END IF;

  IF (SELECT location_revision FROM assets WHERE id = v_asset) <> v_revision + 1 THEN
    RAISE EXCEPTION 'asset_mvp_test: revision changed more than once';
  END IF;
  IF (SELECT current_room_id FROM assets WHERE id = v_asset) <> v_to THEN
    RAISE EXCEPTION 'asset_mvp_test: confirmed room mismatch';
  END IF;
  IF (SELECT count(*) FROM location_audit_events WHERE transfer_id = v_transfer) <> 1 THEN
    RAISE EXCEPTION 'asset_mvp_test: confirm did not write exactly one audit row';
  END IF;

  -- Backstop: a second audit for the same transfer is rejected even if the
  -- write-path GUC is set. The failed insert rolls back inside this block.
  BEGIN
    PERFORM set_config('app.write_path', 'confirm_transfer', true);
    INSERT INTO location_audit_events (
      asset_id, transfer_id, event_type, from_room_id, to_room_id, location_revision
    ) VALUES (
      v_asset, v_transfer, 'transfer_confirmed', v_from, v_to, v_revision + 1
    );
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN unique_violation THEN
      NULL;
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
        RAISE EXCEPTION 'asset_mvp_test: duplicate confirm audit was stored';
      END IF;
      RAISE EXCEPTION 'asset_mvp_test: unexpected duplicate audit error: %', SQLERRM;
  END;

  v_unplaced := register_asset('AST-SYN-004', 'Synthetic unplaced crate', NULL);
  SELECT id INTO v_room FROM rooms WHERE code = 'RM-101';
  v_second := initiate_transfer(v_unplaced, v_room);
  IF confirm_transfer(v_second) <> 'confirmed' THEN
    RAISE EXCEPTION 'asset_mvp_test: placement confirm failed';
  END IF;
  IF confirm_transfer(v_second) <> 'already_confirmed' THEN
    RAISE EXCEPTION 'asset_mvp_test: placement confirm was not idempotent';
  END IF;
  IF (SELECT current_room_id FROM assets WHERE id = v_unplaced) <> v_room THEN
    RAISE EXCEPTION 'asset_mvp_test: unplaced asset was not placed';
  END IF;
  IF (SELECT count(*) FROM location_audit_events WHERE asset_id = v_unplaced) <> 2 THEN
    RAISE EXCEPTION 'asset_mvp_test: placement audit count';
  END IF;

  IF NOT location_audit_is_consistent() THEN
    RAISE EXCEPTION 'asset_mvp_test: idempotency checks left the audit inconsistent';
  END IF;
END;
$test$;
