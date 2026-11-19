DO $test$
DECLARE
  v_cabinet uuid;
  v_room_101 uuid;
  v_room_102 uuid;
  v_gltf uuid;
  v_unmatched uuid;
  v_outcome text;
  v_review uuid;
  v_again uuid;
  v_transfers bigint;
BEGIN
  SELECT id INTO v_cabinet FROM assets WHERE asset_tag = 'AST-SYN-001';
  SELECT id INTO v_room_101 FROM rooms WHERE code = 'RM-101';
  SELECT id INTO v_room_102 FROM rooms WHERE code = 'RM-102';
  SELECT mv.id INTO v_gltf
  FROM model_versions mv
  JOIN buildings b ON b.id = mv.building_id
  WHERE b.code = 'BLD-NORTH' AND mv.label = 'syn-gltf-v1';
  SELECT id INTO v_unmatched
  FROM model_objects
  WHERE stable_id = 'syn.asset.unmatched';
  SELECT count(*) INTO v_transfers FROM transfers WHERE asset_id = v_cabinet;

  SELECT r.outcome, r.review_id
    INTO v_outcome, v_review
  FROM flag_custody_room_mismatch(
    v_cabinet,
    v_gltf,
    v_room_101,
    'Synthetic observation disagrees with the custody room'
  ) r;
  IF v_outcome <> 'needs_review' OR v_review IS NULL THEN
    RAISE EXCEPTION 'asset_mvp_test: custody disagreement was not reviewed';
  END IF;
  IF (SELECT current_room_id FROM assets WHERE id = v_cabinet) <> v_room_102 THEN
    RAISE EXCEPTION 'asset_mvp_test: custody flag moved the cabinet';
  END IF;
  IF (SELECT count(*) FROM transfers WHERE asset_id = v_cabinet) <> v_transfers THEN
    RAISE EXCEPTION 'asset_mvp_test: custody flag created a transfer';
  END IF;

  UPDATE mapping_reviews SET status = 'resolved' WHERE id = v_review;
  IF (SELECT current_room_id FROM assets WHERE id = v_cabinet) <> v_room_102 THEN
    RAISE EXCEPTION 'asset_mvp_test: resolving a custody review moved the cabinet';
  END IF;

  SELECT r.outcome, r.review_id
    INTO v_outcome, v_review
  FROM flag_custody_room_mismatch(
    v_cabinet,
    v_gltf,
    v_room_102,
    'Synthetic observation matches the custody room'
  ) r;
  IF v_outcome <> 'no_mismatch' OR v_review IS NOT NULL THEN
    RAISE EXCEPTION 'asset_mvp_test: matching observation opened a review';
  END IF;

  SELECT r.outcome, r.review_id
    INTO v_outcome, v_review
  FROM open_unmatched_object_review(v_unmatched) r;
  IF v_outcome <> 'opened' THEN
    RAISE EXCEPTION 'asset_mvp_test: unmatched object review did not open';
  END IF;
  SELECT r.outcome, r.review_id
    INTO v_outcome, v_again
  FROM open_unmatched_object_review(v_unmatched) r;
  IF v_outcome <> 'already_open' OR v_again <> v_review THEN
    RAISE EXCEPTION 'asset_mvp_test: unmatched review was duplicated';
  END IF;
  IF EXISTS (
    SELECT 1 FROM asset_model_mappings WHERE model_object_id = v_unmatched
  ) THEN
    RAISE EXCEPTION 'asset_mvp_test: unmatched review assigned an asset';
  END IF;

  SELECT r.outcome INTO v_outcome
  FROM open_unmatched_object_review((
    SELECT id FROM model_objects WHERE stable_id = 'syn.asset.cabinet'
  )) r;
  IF v_outcome <> 'already_mapped' THEN
    RAISE EXCEPTION 'asset_mvp_test: mapped object was treated as unmatched';
  END IF;

  PERFORM set_config('app.write_path', 'confirm_transfer', true);
  BEGIN
    UPDATE location_audit_events
       SET occurred_at = now()
     WHERE asset_id = v_cabinet;
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%asset_mvp: location_audit_events are append-only%' THEN
        IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
          RAISE EXCEPTION 'asset_mvp_test: audit row was updated';
        END IF;
        RAISE EXCEPTION 'asset_mvp_test: unexpected audit update error: %', SQLERRM;
      END IF;
  END;
  BEGIN
    DELETE FROM location_audit_events WHERE asset_id = v_cabinet;
    RAISE EXCEPTION 'asset_mvp_test: expected failure';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM NOT LIKE '%asset_mvp: location_audit_events are append-only%' THEN
        IF SQLERRM LIKE '%asset_mvp_test: expected failure%' THEN
          RAISE EXCEPTION 'asset_mvp_test: audit row was deleted';
        END IF;
        RAISE EXCEPTION 'asset_mvp_test: unexpected audit delete error: %', SQLERRM;
      END IF;
  END;

  IF NOT location_audit_is_consistent() THEN
    RAISE EXCEPTION 'asset_mvp_test: custody checks left the audit inconsistent';
  END IF;
END;
$test$;
