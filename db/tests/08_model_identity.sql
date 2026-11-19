DO $test$
DECLARE
  v_gltf uuid;
  v_ifc uuid;
  v_north uuid;
  v_v2 uuid;
  v_outcome text;
  v_object uuid;
  v_existing uuid;
  v_review uuid;
  v_before_tag text;
  v_count integer;
BEGIN
  SELECT id INTO v_north FROM buildings WHERE code = 'BLD-NORTH';
  SELECT id INTO v_gltf
  FROM model_versions
  WHERE building_id = v_north AND label = 'syn-gltf-v1';
  SELECT id INTO v_ifc
  FROM model_versions
  WHERE building_id = v_north AND label = 'syn-ifc-v1';
  SELECT id INTO v_existing
  FROM model_objects
  WHERE model_version_id = v_gltf AND stable_id = 'syn.asset.cabinet';

  SELECT count(*) INTO v_count FROM model_objects WHERE model_version_id = v_gltf;
  SELECT r.outcome, r.model_object_id, r.review_id
    INTO v_outcome, v_object, v_review
  FROM register_model_object(v_gltf, 'syn.asset.cabinet', 'gltf_extras', 'asset_anchor') r;
  IF v_outcome <> 'needs_review' OR v_object <> v_existing OR v_review IS NULL THEN
    RAISE EXCEPTION 'asset_mvp_test: duplicate stable id was not sent to review';
  END IF;
  IF (SELECT count(*) FROM model_objects WHERE model_version_id = v_gltf) <> v_count THEN
    RAISE EXCEPTION 'asset_mvp_test: duplicate registration created another object';
  END IF;
  IF (SELECT review_kind FROM mapping_reviews WHERE id = v_review) <> 'duplicate_stable_id' THEN
    RAISE EXCEPTION 'asset_mvp_test: duplicate review kind';
  END IF;
  IF (SELECT asset_id FROM asset_model_mappings WHERE model_object_id = v_existing AND status = 'accepted')
     <> (SELECT id FROM assets WHERE asset_tag = 'AST-SYN-001') THEN
    RAISE EXCEPTION 'asset_mvp_test: duplicate registration reassigned the cabinet';
  END IF;

  SELECT count(*) INTO v_count FROM model_objects;
  SELECT r.outcome, r.model_object_id, r.review_id
    INTO v_outcome, v_object, v_review
  FROM register_model_object(v_gltf, '   ', 'gltf_extras', 'asset_anchor') r;
  IF v_outcome <> 'needs_review' OR v_object IS NOT NULL THEN
    RAISE EXCEPTION 'asset_mvp_test: blank stable id created an object';
  END IF;
  IF (SELECT review_kind FROM mapping_reviews WHERE id = v_review) <> 'missing_stable_id' THEN
    RAISE EXCEPTION 'asset_mvp_test: blank id review kind';
  END IF;

  SELECT r.outcome, r.model_object_id, r.review_id
    INTO v_outcome, v_object, v_review
  FROM register_model_object(v_gltf, '12', 'gltf_extras', 'room') r;
  IF v_outcome <> 'needs_review' OR v_object IS NOT NULL THEN
    RAISE EXCEPTION 'asset_mvp_test: node index was stored as an identity';
  END IF;
  IF (SELECT review_kind FROM mapping_reviews WHERE id = v_review) <> 'rejected_unstable_id' THEN
    RAISE EXCEPTION 'asset_mvp_test: node index review kind';
  END IF;
  IF (SELECT count(*) FROM model_objects) <> v_count THEN
    RAISE EXCEPTION 'asset_mvp_test: rejected identifiers were stored as model objects';
  END IF;

  BEGIN
    PERFORM register_model_object(v_gltf, 'SYN0000000000000000B02', 'ifc_global_id', 'room');
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%asset_mvp: kind_source_mismatch%' THEN
        IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
          RAISE EXCEPTION 'asset_mvp_test: IFC kind was stored on a glTF version';
        END IF;
        RAISE EXCEPTION 'asset_mvp_test: unexpected kind error: %', SQLERRM;
      END IF;
  END;

  BEGIN
    INSERT INTO model_objects (model_version_id, stable_id, stable_id_kind, object_role)
    VALUES (v_gltf, '7', 'gltf_extras', 'room');
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN check_violation THEN
      NULL;
    WHEN OTHERS THEN
      IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
        RAISE EXCEPTION 'asset_mvp_test: raw node index insert succeeded';
      END IF;
      RAISE EXCEPTION 'asset_mvp_test: unexpected raw node index error: %', SQLERRM;
  END;

  -- A UUID-shaped extras value is not rejected. The schema cannot tell an
  -- authored extras UUID from a Three.js runtime UUID. That distinction is
  -- importer behavior, and there is no importer in this starter.
  SELECT r.outcome INTO v_outcome
  FROM register_model_object(
    v_gltf,
    '00000000-0000-4000-8000-00000000abcd',
    'gltf_extras',
    'asset_anchor'
  ) r;
  IF v_outcome <> 'registered' THEN
    RAISE EXCEPTION 'asset_mvp_test: uuid-shaped extras id was rejected by the schema';
  END IF;

  SELECT r.outcome INTO v_outcome
  FROM register_model_object(v_ifc, 'SYN0000000000000000B0', 'ifc_global_id', 'room') r;
  IF v_outcome <> 'needs_review' THEN
    RAISE EXCEPTION 'asset_mvp_test: short IFC id was stored';
  END IF;

  INSERT INTO model_versions (building_id, label, source_kind)
  VALUES (v_north, 'syn-gltf-v2', 'gltf')
  RETURNING id INTO v_v2;
  SELECT r.outcome, r.model_object_id
    INTO v_outcome, v_object
  FROM register_model_object(v_v2, 'syn.asset.cabinet', 'gltf_extras', 'asset_anchor') r;
  IF v_outcome <> 'registered' OR v_object = v_existing THEN
    RAISE EXCEPTION 'asset_mvp_test: a new model version could not keep the same authored id';
  END IF;
  IF EXISTS (
    SELECT 1 FROM asset_model_mappings WHERE model_version_id = v_v2
  ) THEN
    RAISE EXCEPTION 'asset_mvp_test: new model version copied or invented a mapping';
  END IF;
  IF (SELECT status FROM asset_model_mappings
      WHERE model_object_id = v_existing) <> 'accepted' THEN
    RAISE EXCEPTION 'asset_mvp_test: v1 mapping changed when v2 was registered';
  END IF;

  BEGIN
    UPDATE model_objects SET stable_id = 'syn.asset.cabinet-renamed' WHERE id = v_existing;
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%asset_mvp: model object identity is immutable%' THEN
        IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
          RAISE EXCEPTION 'asset_mvp_test: stable id was edited';
        END IF;
        RAISE EXCEPTION 'asset_mvp_test: unexpected stable id update error: %', SQLERRM;
      END IF;
  END;

  BEGIN
    DELETE FROM model_versions WHERE id = v_v2;
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%asset_mvp: model versions are not deleted in this starter%' THEN
        IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
          RAISE EXCEPTION 'asset_mvp_test: model version was deleted';
        END IF;
        RAISE EXCEPTION 'asset_mvp_test: unexpected model version delete error: %', SQLERRM;
      END IF;
  END;

  SELECT asset_tag INTO v_before_tag FROM assets WHERE asset_tag = 'AST-SYN-001';
  IF v_before_tag IS NULL THEN
    RAISE EXCEPTION 'asset_mvp_test: cabinet disappeared during identity checks';
  END IF;
  IF (SELECT r.code
      FROM assets a
      JOIN rooms r ON r.id = a.current_room_id
      WHERE a.asset_tag = 'AST-SYN-001') <> 'RM-102' THEN
    RAISE EXCEPTION 'asset_mvp_test: model identity checks moved the cabinet';
  END IF;
  IF NOT location_audit_is_consistent() THEN
    RAISE EXCEPTION 'asset_mvp_test: model identity checks left the audit inconsistent';
  END IF;
END;
$test$;
