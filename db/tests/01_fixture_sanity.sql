-- Fresh database after db/fixtures/synthetic.sql.
DO $test$
DECLARE
  v_cabinet uuid;
  v_room_101 uuid;
  v_room_102 uuid;
  v_room_201 uuid;
BEGIN
  IF (SELECT count(*) FROM buildings) <> 2 THEN
    RAISE EXCEPTION 'asset_mvp_test: expected 2 buildings';
  END IF;
  IF (SELECT count(*) FROM rooms) <> 3 THEN
    RAISE EXCEPTION 'asset_mvp_test: expected 3 rooms';
  END IF;
  IF NOT location_audit_is_consistent() THEN
    RAISE EXCEPTION 'asset_mvp_test: fixture audit is inconsistent';
  END IF;

  SELECT id INTO v_cabinet FROM assets WHERE asset_tag = 'AST-SYN-001';
  SELECT r.id INTO v_room_101
  FROM rooms r
  JOIN buildings b ON b.id = r.building_id
  WHERE b.code = 'BLD-NORTH' AND r.code = 'RM-101';
  SELECT r.id INTO v_room_102
  FROM rooms r
  JOIN buildings b ON b.id = r.building_id
  WHERE b.code = 'BLD-NORTH' AND r.code = 'RM-102';
  SELECT r.id INTO v_room_201
  FROM rooms r
  JOIN buildings b ON b.id = r.building_id
  WHERE b.code = 'BLD-SOUTH' AND r.code = 'RM-201';

  IF (SELECT current_room_id FROM assets WHERE id = v_cabinet) <> v_room_102 THEN
    RAISE EXCEPTION 'asset_mvp_test: cabinet should be in RM-102 after the fixture transfer';
  END IF;
  IF (SELECT location_revision FROM assets WHERE id = v_cabinet) <> 2 THEN
    RAISE EXCEPTION 'asset_mvp_test: cabinet revision should be 2';
  END IF;
  IF (SELECT count(*) FROM location_audit_events WHERE asset_id = v_cabinet) <> 2 THEN
    RAISE EXCEPTION 'asset_mvp_test: cabinet should have registration plus one confirm';
  END IF;
  IF (SELECT current_room_id FROM assets WHERE asset_tag = 'AST-SYN-002') <> v_room_201 THEN
    RAISE EXCEPTION 'asset_mvp_test: cart moved during fixture load';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM asset_model_mappings m
    JOIN model_objects o ON o.id = m.model_object_id
    JOIN assets a ON a.id = m.asset_id
    WHERE o.stable_id = 'syn.asset.cabinet'
      AND o.stable_id_kind = 'gltf_extras'
      AND a.asset_tag = 'AST-SYN-001'
      AND m.status = 'accepted'
      AND a.id::text IS DISTINCT FROM o.stable_id
  ) THEN
    RAISE EXCEPTION 'asset_mvp_test: cabinet mapping is missing or copies the asset uuid';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM asset_model_mappings m
    JOIN model_objects o ON o.id = m.model_object_id
    WHERE o.stable_id = 'syn.asset.unmatched'
  ) OR EXISTS (
    SELECT 1
    FROM room_model_mappings m
    JOIN model_objects o ON o.id = m.model_object_id
    WHERE o.stable_id = 'syn.asset.unmatched'
  ) THEN
    RAISE EXCEPTION 'asset_mvp_test: unmatched object was assigned';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND column_name IN (
        'three_uuid', 'runtime_uuid', 'node_index', 'object_index', 'object3d_uuid'
      )
  ) THEN
    RAISE EXCEPTION 'asset_mvp_test: a rendering-runtime column is present';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name ~* 'sensor|occupancy|detected_move|geolocation'
  ) THEN
    RAISE EXCEPTION 'asset_mvp_test: a movement-detection table is present';
  END IF;

  -- The accepted room mapping still names RM-101. Custody of the cabinet does not.
  IF (SELECT r.code
      FROM room_model_mappings m
      JOIN model_objects o ON o.id = m.model_object_id
      JOIN rooms r ON r.id = m.room_id
      WHERE o.stable_id = 'syn.room.101' AND m.status = 'accepted') <> 'RM-101' THEN
    RAISE EXCEPTION 'asset_mvp_test: room mapping changed with the cabinet transfer';
  END IF;
  IF v_room_101 = v_room_102 THEN
    RAISE EXCEPTION 'asset_mvp_test: fixture rooms collapsed';
  END IF;
END;
$test$;
