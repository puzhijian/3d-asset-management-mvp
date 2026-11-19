-- Synthetic catalog for a fresh database. Not people, customers, or sites.
-- Labels are invented for schema checks. Loading this file twice will fail.
--
-- Story after this file commits:
--   BLD-NORTH / RM-101 and RM-102, BLD-SOUTH / RM-201.
--   AST-SYN-001 "Synthetic cabinet" was registered in RM-101, then one
--   confirmed transfer moved its custody record to RM-102.
--   AST-SYN-002 "Synthetic cart" stays in RM-201.
--   The cabinet's accepted glTF mapping still points at the same authored
--   extras id. That mapping is not its custody room.
--   syn.asset.unmatched is a model object with no asset assignment.

BEGIN;

DO $fixture$
DECLARE
  v_north uuid;
  v_south uuid;
  v_room_101 uuid;
  v_room_102 uuid;
  v_room_201 uuid;
  v_cabinet uuid;
  v_cart uuid;
  v_gltf uuid;
  v_ifc uuid;
  v_outcome text;
  v_object uuid;
  v_review uuid;
  v_mapping uuid;
  v_transfer uuid;
  v_result text;
BEGIN
  INSERT INTO buildings (code, name)
  VALUES ('BLD-NORTH', 'Synthetic North Hall')
  RETURNING id INTO v_north;

  INSERT INTO buildings (code, name)
  VALUES ('BLD-SOUTH', 'Synthetic South Annex')
  RETURNING id INTO v_south;

  INSERT INTO rooms (building_id, code, name)
  VALUES (v_north, 'RM-101', 'Synthetic Room 101')
  RETURNING id INTO v_room_101;

  INSERT INTO rooms (building_id, code, name)
  VALUES (v_north, 'RM-102', 'Synthetic Room 102')
  RETURNING id INTO v_room_102;

  INSERT INTO rooms (building_id, code, name)
  VALUES (v_south, 'RM-201', 'Synthetic Room 201')
  RETURNING id INTO v_room_201;

  v_cabinet := register_asset('AST-SYN-001', 'Synthetic cabinet', v_room_101);
  v_cart := register_asset('AST-SYN-002', 'Synthetic cart', v_room_201);

  INSERT INTO model_versions (building_id, label, source_kind)
  VALUES (v_north, 'syn-gltf-v1', 'gltf')
  RETURNING id INTO v_gltf;

  INSERT INTO model_versions (building_id, label, source_kind)
  VALUES (v_north, 'syn-ifc-v1', 'ifc')
  RETURNING id INTO v_ifc;

  SELECT r.outcome, r.model_object_id, r.review_id
    INTO v_outcome, v_object, v_review
  FROM register_model_object(v_gltf, 'syn.room.101', 'gltf_extras', 'room') r;
  IF v_outcome <> 'registered' OR v_review IS NOT NULL THEN
    RAISE EXCEPTION 'fixture: room object was not registered cleanly';
  END IF;

  SELECT r.outcome, r.mapping_id, r.review_id
    INTO v_outcome, v_mapping, v_review
  FROM propose_room_mapping(v_gltf, v_object, v_room_101) r;
  IF v_outcome <> 'proposed' THEN
    RAISE EXCEPTION 'fixture: room mapping was not proposed';
  END IF;
  v_result := accept_room_mapping(v_mapping);
  IF v_result <> 'accepted' THEN
    RAISE EXCEPTION 'fixture: room mapping was not accepted';
  END IF;

  SELECT r.outcome, r.model_object_id, r.review_id
    INTO v_outcome, v_object, v_review
  FROM register_model_object(v_gltf, 'syn.asset.cabinet', 'gltf_extras', 'asset_anchor') r;
  IF v_outcome <> 'registered' THEN
    RAISE EXCEPTION 'fixture: cabinet object was not registered';
  END IF;
  v_mapping := propose_asset_mapping(v_gltf, v_object, v_cabinet);
  v_result := accept_asset_mapping(v_mapping);
  IF v_result <> 'accepted' THEN
    RAISE EXCEPTION 'fixture: cabinet mapping was not accepted';
  END IF;

  SELECT r.outcome, r.review_id
    INTO v_outcome, v_review
  FROM register_model_object(v_gltf, 'syn.asset.unmatched', 'gltf_extras', 'asset_anchor') r;
  IF v_outcome <> 'registered' OR v_review IS NOT NULL THEN
    RAISE EXCEPTION 'fixture: unmatched object should be registered without a review';
  END IF;

  -- 22-character synthetic IFC GlobalId. Not a real model identifier.
  SELECT r.outcome, r.model_object_id, r.review_id
    INTO v_outcome, v_object, v_review
  FROM register_model_object(
    v_ifc, 'SYN0000000000000000A01', 'ifc_global_id', 'room'
  ) r;
  IF v_outcome <> 'registered' THEN
    RAISE EXCEPTION 'fixture: IFC room object was not registered';
  END IF;
  IF length('SYN0000000000000000A01') <> 22 THEN
    RAISE EXCEPTION 'fixture: synthetic IFC id length drifted';
  END IF;

  SELECT r.outcome, r.mapping_id
    INTO v_outcome, v_mapping
  FROM propose_room_mapping(v_ifc, v_object, v_room_101) r;
  IF v_outcome <> 'proposed' OR accept_room_mapping(v_mapping) <> 'accepted' THEN
    RAISE EXCEPTION 'fixture: IFC room mapping was not accepted';
  END IF;

  v_transfer := initiate_transfer(v_cabinet, v_room_102);
  v_result := confirm_transfer(v_transfer);
  IF v_result <> 'confirmed' THEN
    RAISE EXCEPTION 'fixture: cabinet transfer was not confirmed';
  END IF;

  IF (SELECT current_room_id FROM assets WHERE id = v_cabinet) <> v_room_102 THEN
    RAISE EXCEPTION 'fixture: cabinet custody room was not updated';
  END IF;
  IF (SELECT current_room_id FROM assets WHERE id = v_cart) <> v_room_201 THEN
    RAISE EXCEPTION 'fixture: cart custody room changed';
  END IF;
  IF NOT location_audit_is_consistent() THEN
    RAISE EXCEPTION 'fixture: location audit is inconsistent';
  END IF;
END;
$fixture$;

COMMIT;
