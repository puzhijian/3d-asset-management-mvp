DO $test$
DECLARE
  v_gltf uuid;
  v_object uuid;
  v_south_room uuid;
  v_cabinet uuid;
  v_cart uuid;
  v_cart_room uuid;
  v_outcome text;
  v_mapping uuid;
  v_review uuid;
  v_second uuid;
  v_accepted uuid;
BEGIN
  SELECT mv.id INTO v_gltf
  FROM model_versions mv
  JOIN buildings b ON b.id = mv.building_id
  WHERE b.code = 'BLD-NORTH' AND mv.label = 'syn-gltf-v1';
  SELECT id INTO v_object
  FROM model_objects
  WHERE model_version_id = v_gltf AND stable_id = 'syn.room.101';
  SELECT id INTO v_south_room FROM rooms WHERE code = 'RM-201';
  SELECT id, current_room_id INTO v_cabinet, v_cart_room FROM assets WHERE asset_tag = 'AST-SYN-001';
  SELECT id, current_room_id INTO v_cart, v_cart_room FROM assets WHERE asset_tag = 'AST-SYN-002';

  SELECT r.outcome, r.mapping_id, r.review_id
    INTO v_outcome, v_mapping, v_review
  FROM propose_room_mapping(v_gltf, v_object, v_south_room) r;
  IF v_outcome <> 'needs_review' OR v_mapping IS NOT NULL OR v_review IS NULL THEN
    RAISE EXCEPTION 'asset_mvp_test: cross-building room link was not reviewed';
  END IF;
  IF (SELECT review_kind FROM mapping_reviews WHERE id = v_review) <> 'room_building_mismatch' THEN
    RAISE EXCEPTION 'asset_mvp_test: room mismatch kind';
  END IF;
  IF EXISTS (
    SELECT 1 FROM room_model_mappings
    WHERE model_object_id = v_object AND room_id = v_south_room
  ) THEN
    RAISE EXCEPTION 'asset_mvp_test: mismatched room mapping row was written';
  END IF;

  BEGIN
    INSERT INTO room_model_mappings (model_version_id, model_object_id, room_id, status)
    VALUES (v_gltf, v_object, v_south_room, 'accepted');
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%asset_mvp: room_building_mismatch%' THEN
        IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
          RAISE EXCEPTION 'asset_mvp_test: raw mismatched room mapping succeeded';
        END IF;
        RAISE EXCEPTION 'asset_mvp_test: unexpected mismatch insert error: %', SQLERRM;
      END IF;
  END;

  SELECT m.id INTO v_accepted
  FROM asset_model_mappings m
  JOIN model_objects o ON o.id = m.model_object_id
  WHERE o.stable_id = 'syn.asset.cabinet' AND m.status = 'accepted';

  BEGIN
    UPDATE asset_model_mappings
       SET asset_id = v_cart
     WHERE id = v_accepted;
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%asset_mvp: mapping fields other than status are immutable%' THEN
        IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
          RAISE EXCEPTION 'asset_mvp_test: accepted mapping was reassigned';
        END IF;
        RAISE EXCEPTION 'asset_mvp_test: unexpected reassignment error: %', SQLERRM;
      END IF;
  END;

  BEGIN
    UPDATE asset_model_mappings SET status = 'rejected' WHERE id = v_accepted;
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%asset_mvp: accepted mappings are immutable%' THEN
        IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
          RAISE EXCEPTION 'asset_mvp_test: accepted mapping status was changed';
        END IF;
        RAISE EXCEPTION 'asset_mvp_test: unexpected accepted-status error: %', SQLERRM;
      END IF;
  END;

  SELECT r.outcome, r.model_object_id
    INTO v_outcome, v_object
  FROM register_model_object(v_gltf, 'syn.asset.cart', 'gltf_extras', 'asset_anchor') r;
  v_mapping := propose_asset_mapping(v_gltf, v_object, v_cart);
  IF accept_asset_mapping(v_mapping) <> 'accepted' THEN
    RAISE EXCEPTION 'asset_mvp_test: cross-building asset link was rejected';
  END IF;
  IF accept_asset_mapping(v_mapping) <> 'already_accepted' THEN
    RAISE EXCEPTION 'asset_mvp_test: accept was not idempotent';
  END IF;

  v_second := propose_asset_mapping(v_gltf, v_object, v_cabinet);
  BEGIN
    PERFORM accept_asset_mapping(v_second);
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN unique_violation THEN
      NULL;
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
        RAISE EXCEPTION 'asset_mvp_test: a second accepted asset mapping was stored';
      END IF;
      RAISE EXCEPTION 'asset_mvp_test: unexpected second accept error: %', SQLERRM;
  END;

  IF (SELECT asset_id FROM asset_model_mappings WHERE id = v_mapping) <> v_cart THEN
    RAISE EXCEPTION 'asset_mvp_test: failed second accept replaced the first asset';
  END IF;
  IF (SELECT current_room_id FROM assets WHERE id = v_cart) <> v_cart_room THEN
    RAISE EXCEPTION 'asset_mvp_test: asset mapping changed custody room';
  END IF;
  IF (SELECT r.code FROM assets a JOIN rooms r ON r.id = a.current_room_id
      WHERE a.id = v_cabinet) <> 'RM-102' THEN
    RAISE EXCEPTION 'asset_mvp_test: cabinet custody changed during mapping checks';
  END IF;

  UPDATE mapping_reviews SET status = 'resolved' WHERE id = v_review;
  IF EXISTS (
    SELECT 1 FROM room_model_mappings WHERE model_object_id = (
      SELECT model_object_id FROM mapping_reviews WHERE id = v_review
    ) AND room_id = v_south_room
  ) THEN
    RAISE EXCEPTION 'asset_mvp_test: resolving a review wrote a room mapping';
  END IF;

  BEGIN
    UPDATE mapping_reviews SET asset_id = v_cart WHERE id = v_review;
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%asset_mvp: review subject is immutable%' THEN
        IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
          RAISE EXCEPTION 'asset_mvp_test: resolved review was edited into an assignment';
        END IF;
        RAISE EXCEPTION 'asset_mvp_test: unexpected review edit error: %', SQLERRM;
      END IF;
  END;

  IF NOT location_audit_is_consistent() THEN
    RAISE EXCEPTION 'asset_mvp_test: mapping checks left the audit inconsistent';
  END IF;
END;
$test$;
