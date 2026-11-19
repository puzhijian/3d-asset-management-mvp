DO $test$
DECLARE
  v_north uuid;
  v_south uuid;
  v_asset uuid;
  v_missing uuid := '00000000-0000-4000-8000-0000000000ff';
BEGIN
  SELECT id INTO v_north FROM buildings WHERE code = 'BLD-NORTH';
  SELECT id INTO v_south FROM buildings WHERE code = 'BLD-SOUTH';
  SELECT id INTO v_asset FROM assets WHERE asset_tag = 'AST-SYN-002';

  BEGIN
    INSERT INTO rooms (building_id, code, name)
    VALUES (v_south, 'RM-101', 'Synthetic South Room 101');
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'asset_mvp_test: room codes are unique per building, got %', SQLERRM;
  END;

  BEGIN
    INSERT INTO rooms (building_id, code, name)
    VALUES (v_missing, 'RM-301', 'Synthetic missing building');
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN foreign_key_violation THEN
      NULL;
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
        RAISE;
      END IF;
      RAISE EXCEPTION 'asset_mvp_test: unexpected error for missing building: %', SQLERRM;
  END;

  BEGIN
    PERFORM initiate_transfer(v_asset, v_missing);
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%asset_mvp: room_not_found%' THEN
        IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
          RAISE EXCEPTION 'asset_mvp_test: missing room was accepted';
        END IF;
        RAISE EXCEPTION 'asset_mvp_test: unexpected initiate error: %', SQLERRM;
      END IF;
  END;

  BEGIN
    PERFORM set_config('app.write_path', '', true);
    INSERT INTO transfers (asset_id, from_room_id, to_room_id, expected_location_revision)
    VALUES (v_asset, NULL, (SELECT id FROM rooms WHERE code = 'RM-102'), 1);
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%asset_mvp: transfers are created only by initiate_transfer%' THEN
        IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
          RAISE EXCEPTION 'asset_mvp_test: raw transfer insert succeeded';
        END IF;
        RAISE EXCEPTION 'asset_mvp_test: unexpected raw transfer error: %', SQLERRM;
      END IF;
  END;

  BEGIN
    DELETE FROM rooms WHERE code = 'RM-201';
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN foreign_key_violation THEN
      NULL;
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
        RAISE EXCEPTION 'asset_mvp_test: occupied room was deleted';
      END IF;
      RAISE EXCEPTION 'asset_mvp_test: unexpected room delete error: %', SQLERRM;
  END;

  BEGIN
    DELETE FROM assets WHERE asset_tag = 'AST-SYN-002';
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN foreign_key_violation THEN
      NULL;
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
        RAISE EXCEPTION 'asset_mvp_test: asset with audit history was deleted';
      END IF;
      RAISE EXCEPTION 'asset_mvp_test: unexpected asset delete error: %', SQLERRM;
  END;

  BEGIN
    DELETE FROM buildings WHERE code = 'BLD-NORTH';
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN foreign_key_violation THEN
      NULL;
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
        RAISE EXCEPTION 'asset_mvp_test: building with rooms was deleted';
      END IF;
      RAISE EXCEPTION 'asset_mvp_test: unexpected building delete error: %', SQLERRM;
  END;

  BEGIN
    DELETE FROM transfers
    WHERE asset_id = (SELECT id FROM assets WHERE asset_tag = 'AST-SYN-001');
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%asset_mvp: transfers are not deleted%' THEN
        IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
          RAISE EXCEPTION 'asset_mvp_test: transfer row was deleted';
        END IF;
        RAISE EXCEPTION 'asset_mvp_test: unexpected transfer delete error: %', SQLERRM;
      END IF;
  END;

  IF NOT location_audit_is_consistent() THEN
    RAISE EXCEPTION 'asset_mvp_test: integrity checks left the audit inconsistent';
  END IF;
END;
$test$;
