-- 3D asset management MVP — initial PostgreSQL schema.
-- This is a database starter, not an application.
-- It does not parse glTF or IFC, does not run Three.js, and does not detect
-- physical movement. See README.md and docs/architecture.md.
--
-- Write gate: ordinary statements cannot change an asset's current room or
-- append a location audit row. confirm_transfer and registration set the
-- transaction-local custom GUC app.write_path. That GUC is not a privilege
-- boundary. A role that can write the tables and set the GUC can still record
-- a forged but internally consistent move. An inconsistent location/audit pair
-- is rejected at COMMIT by a deferred constraint trigger. That trigger scans
-- the custody tables; it is a starter-scale check, not a production indexing
-- design. Closing the privilege gap is documented future work, not done here.

BEGIN;

CREATE TABLE buildings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL,
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT buildings_code_unique UNIQUE (code),
  CONSTRAINT buildings_code_shape CHECK (
    code = btrim(code)
    AND code ~ '^[A-Z0-9][A-Z0-9-]{0,62}$'
  ),
  CONSTRAINT buildings_name_shape CHECK (
    name = btrim(name)
    AND length(name) BETWEEN 1 AND 200
  )
);

CREATE TABLE rooms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  building_id uuid NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT rooms_building_id_fkey
    FOREIGN KEY (building_id) REFERENCES buildings (id) ON DELETE RESTRICT,
  CONSTRAINT rooms_code_unique_per_building UNIQUE (building_id, code),
  CONSTRAINT rooms_code_shape CHECK (
    code = btrim(code)
    AND code ~ '^[A-Z0-9][A-Z0-9-]{0,62}$'
  ),
  CONSTRAINT rooms_name_shape CHECK (
    name = btrim(name)
    AND length(name) BETWEEN 1 AND 200
  )
);

CREATE INDEX rooms_building_id_idx ON rooms (building_id);

-- Custody identity. id is assigned here and is not a Three.js object UUID,
-- a glTF node index, or an IFC GlobalId. asset_tag is the human custody tag
-- and is also immutable. Neither column is a rendering identifier.
CREATE TABLE assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_tag text NOT NULL,
  name text NOT NULL,
  current_room_id uuid,
  location_revision bigint NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT assets_asset_tag_unique UNIQUE (asset_tag),
  CONSTRAINT assets_asset_tag_shape CHECK (
    asset_tag = btrim(asset_tag)
    AND asset_tag ~ '^[A-Z0-9][A-Z0-9-]{0,62}$'
  ),
  CONSTRAINT assets_name_shape CHECK (
    name = btrim(name)
    AND length(name) BETWEEN 1 AND 200
  ),
  CONSTRAINT assets_current_room_id_fkey
    FOREIGN KEY (current_room_id) REFERENCES rooms (id) ON DELETE RESTRICT,
  CONSTRAINT assets_location_revision_check CHECK (location_revision > 0)
);

CREATE INDEX assets_current_room_id_idx ON assets (current_room_id);

CREATE TABLE transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_id uuid NOT NULL,
  from_room_id uuid,
  to_room_id uuid NOT NULL,
  expected_location_revision bigint NOT NULL,
  status text NOT NULL DEFAULT 'initiated',
  initiated_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  CONSTRAINT transfers_asset_id_fkey
    FOREIGN KEY (asset_id) REFERENCES assets (id) ON DELETE RESTRICT,
  CONSTRAINT transfers_from_room_id_fkey
    FOREIGN KEY (from_room_id) REFERENCES rooms (id) ON DELETE RESTRICT,
  CONSTRAINT transfers_to_room_id_fkey
    FOREIGN KEY (to_room_id) REFERENCES rooms (id) ON DELETE RESTRICT,
  CONSTRAINT transfers_status_check CHECK (
    status IN ('initiated', 'confirmed', 'conflict', 'cancelled')
  ),
  CONSTRAINT transfers_expected_revision_check CHECK (expected_location_revision > 0),
  CONSTRAINT transfers_rooms_differ CHECK (from_room_id IS DISTINCT FROM to_room_id),
  CONSTRAINT transfers_resolved_at_check CHECK (
    (status = 'initiated' AND resolved_at IS NULL)
    OR (status IN ('confirmed', 'conflict', 'cancelled') AND resolved_at IS NOT NULL)
  )
);

CREATE INDEX transfers_asset_id_idx ON transfers (asset_id);
CREATE INDEX transfers_status_idx ON transfers (status);

-- Append-only custody history. Rows are inserted by registration and by
-- confirm_transfer. UPDATE and DELETE are rejected even if app.write_path is set.
CREATE TABLE location_audit_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  asset_id uuid NOT NULL,
  transfer_id uuid,
  event_type text NOT NULL,
  from_room_id uuid,
  to_room_id uuid,
  location_revision bigint NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT location_audit_events_asset_id_fkey
    FOREIGN KEY (asset_id) REFERENCES assets (id) ON DELETE RESTRICT,
  CONSTRAINT location_audit_events_transfer_id_fkey
    FOREIGN KEY (transfer_id) REFERENCES transfers (id) ON DELETE RESTRICT,
  CONSTRAINT location_audit_events_from_room_id_fkey
    FOREIGN KEY (from_room_id) REFERENCES rooms (id) ON DELETE RESTRICT,
  CONSTRAINT location_audit_events_to_room_id_fkey
    FOREIGN KEY (to_room_id) REFERENCES rooms (id) ON DELETE RESTRICT,
  CONSTRAINT location_audit_events_shape CHECK (
    (
      event_type = 'initial_placement'
      AND transfer_id IS NULL
      AND from_room_id IS NULL
      AND to_room_id IS NOT NULL
      AND location_revision = 1
    )
    OR (
      event_type = 'registered_unplaced'
      AND transfer_id IS NULL
      AND from_room_id IS NULL
      AND to_room_id IS NULL
      AND location_revision = 1
    )
    OR (
      event_type = 'transfer_confirmed'
      AND transfer_id IS NOT NULL
      AND to_room_id IS NOT NULL
      AND from_room_id IS DISTINCT FROM to_room_id
      AND location_revision > 1
    )
  )
);

CREATE UNIQUE INDEX location_audit_events_one_per_revision
  ON location_audit_events (asset_id, location_revision);

CREATE UNIQUE INDEX location_audit_events_one_confirm_per_transfer
  ON location_audit_events (transfer_id)
  WHERE event_type = 'transfer_confirmed';

CREATE INDEX location_audit_events_asset_revision_idx
  ON location_audit_events (asset_id, location_revision);

-- One authored publication of a building model. A later file is a new row.
-- Geometry bytes are not stored in this starter.
CREATE TABLE model_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  building_id uuid NOT NULL,
  label text NOT NULL,
  source_kind text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT model_versions_building_id_fkey
    FOREIGN KEY (building_id) REFERENCES buildings (id) ON DELETE RESTRICT,
  CONSTRAINT model_versions_label_unique UNIQUE (building_id, label),
  CONSTRAINT model_versions_label_shape CHECK (
    label = btrim(label)
    AND length(label) BETWEEN 1 AND 120
  ),
  CONSTRAINT model_versions_source_kind_check CHECK (source_kind IN ('gltf', 'ifc'))
);

CREATE INDEX model_versions_building_id_idx ON model_versions (building_id);

-- Authored stable identity for one object inside one model version.
-- stable_id_kind is only gltf_extras or ifc_global_id.
-- There is no column for a Three.js runtime UUID or a node index.
CREATE TABLE model_objects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  model_version_id uuid NOT NULL,
  stable_id text NOT NULL,
  stable_id_kind text NOT NULL,
  object_role text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT model_objects_model_version_id_fkey
    FOREIGN KEY (model_version_id) REFERENCES model_versions (id) ON DELETE RESTRICT,
  CONSTRAINT model_objects_stable_id_unique
    UNIQUE (model_version_id, stable_id_kind, stable_id),
  CONSTRAINT model_objects_stable_id_shape CHECK (
    length(stable_id) BETWEEN 1 AND 128
    AND stable_id = btrim(stable_id)
    AND (
      stable_id_kind = 'ifc_global_id'
      OR stable_id !~ '^[0-9]+$'
    )
  ),
  CONSTRAINT model_objects_stable_id_kind_check CHECK (
    stable_id_kind IN ('gltf_extras', 'ifc_global_id')
  ),
  CONSTRAINT model_objects_ifc_global_id_shape CHECK (
    stable_id_kind <> 'ifc_global_id'
    OR stable_id ~ '^[0-9A-Za-z_$]{22}$'
  ),
  CONSTRAINT model_objects_object_role_check CHECK (
    object_role IN ('room', 'asset_anchor')
  )
);

CREATE INDEX model_objects_model_version_id_idx ON model_objects (model_version_id);

-- Identity link only. Accepting a row does not change assets.current_room_id.
CREATE TABLE asset_model_mappings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  model_version_id uuid NOT NULL,
  model_object_id uuid NOT NULL,
  asset_id uuid NOT NULL,
  status text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT asset_model_mappings_model_version_id_fkey
    FOREIGN KEY (model_version_id) REFERENCES model_versions (id) ON DELETE RESTRICT,
  CONSTRAINT asset_model_mappings_model_object_id_fkey
    FOREIGN KEY (model_object_id) REFERENCES model_objects (id) ON DELETE RESTRICT,
  CONSTRAINT asset_model_mappings_asset_id_fkey
    FOREIGN KEY (asset_id) REFERENCES assets (id) ON DELETE RESTRICT,
  CONSTRAINT asset_model_mappings_status_check CHECK (
    status IN ('proposed', 'accepted', 'rejected')
  )
);

CREATE UNIQUE INDEX asset_model_mappings_one_accepted_object
  ON asset_model_mappings (model_object_id)
  WHERE status = 'accepted';

CREATE UNIQUE INDEX asset_model_mappings_one_accepted_asset_per_version
  ON asset_model_mappings (model_version_id, asset_id)
  WHERE status = 'accepted';

CREATE INDEX asset_model_mappings_asset_id_idx ON asset_model_mappings (asset_id);

CREATE TABLE room_model_mappings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  model_version_id uuid NOT NULL,
  model_object_id uuid NOT NULL,
  room_id uuid NOT NULL,
  status text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT room_model_mappings_model_version_id_fkey
    FOREIGN KEY (model_version_id) REFERENCES model_versions (id) ON DELETE RESTRICT,
  CONSTRAINT room_model_mappings_model_object_id_fkey
    FOREIGN KEY (model_object_id) REFERENCES model_objects (id) ON DELETE RESTRICT,
  CONSTRAINT room_model_mappings_room_id_fkey
    FOREIGN KEY (room_id) REFERENCES rooms (id) ON DELETE RESTRICT,
  CONSTRAINT room_model_mappings_status_check CHECK (
    status IN ('proposed', 'accepted', 'rejected')
  )
);

CREATE UNIQUE INDEX room_model_mappings_one_accepted_object
  ON room_model_mappings (model_object_id)
  WHERE status = 'accepted';

CREATE UNIQUE INDEX room_model_mappings_one_accepted_room_per_version
  ON room_model_mappings (model_version_id, room_id)
  WHERE status = 'accepted';

CREATE INDEX room_model_mappings_room_id_idx ON room_model_mappings (room_id);

-- A review records a problem. Resolving it does not assign an asset, rewrite a
-- mapping, or move a room. There is no application step in this starter.
CREATE TABLE mapping_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  model_version_id uuid NOT NULL,
  review_kind text NOT NULL,
  status text NOT NULL DEFAULT 'open',
  stable_id text,
  stable_id_kind text,
  model_object_id uuid,
  room_id uuid,
  asset_id uuid,
  detail text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT mapping_reviews_model_version_id_fkey
    FOREIGN KEY (model_version_id) REFERENCES model_versions (id) ON DELETE RESTRICT,
  CONSTRAINT mapping_reviews_model_object_id_fkey
    FOREIGN KEY (model_object_id) REFERENCES model_objects (id) ON DELETE RESTRICT,
  CONSTRAINT mapping_reviews_room_id_fkey
    FOREIGN KEY (room_id) REFERENCES rooms (id) ON DELETE RESTRICT,
  CONSTRAINT mapping_reviews_asset_id_fkey
    FOREIGN KEY (asset_id) REFERENCES assets (id) ON DELETE RESTRICT,
  CONSTRAINT mapping_reviews_kind_check CHECK (
    review_kind IN (
      'missing_stable_id',
      'duplicate_stable_id',
      'rejected_unstable_id',
      'room_building_mismatch',
      'unmatched_model_object',
      'custody_room_mismatch'
    )
  ),
  CONSTRAINT mapping_reviews_status_check CHECK (status IN ('open', 'resolved')),
  CONSTRAINT mapping_reviews_stable_id_len CHECK (
    stable_id IS NULL OR length(stable_id) BETWEEN 1 AND 128
  ),
  CONSTRAINT mapping_reviews_stable_id_kind_check CHECK (
    stable_id_kind IS NULL
    OR stable_id_kind IN ('gltf_extras', 'ifc_global_id')
  ),
  CONSTRAINT mapping_reviews_detail_shape CHECK (
    length(btrim(detail)) BETWEEN 1 AND 500
  )
);

CREATE UNIQUE INDEX mapping_reviews_one_open_unmatched
  ON mapping_reviews (model_object_id)
  WHERE review_kind = 'unmatched_model_object' AND status = 'open';

CREATE INDEX mapping_reviews_open_kind_idx
  ON mapping_reviews (status, review_kind);

CREATE FUNCTION assets_before_write() RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $fn$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.location_revision <> 1 THEN
      RAISE EXCEPTION 'asset_mvp: new assets start at location_revision 1';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.id IS DISTINCT FROM OLD.id OR NEW.asset_tag IS DISTINCT FROM OLD.asset_tag THEN
    RAISE EXCEPTION 'asset_mvp: asset id and asset_tag are immutable';
  END IF;
  IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'asset_mvp: asset created_at is immutable';
  END IF;
  IF NEW.current_room_id IS DISTINCT FROM OLD.current_room_id
     OR NEW.location_revision IS DISTINCT FROM OLD.location_revision THEN
    IF current_setting('app.write_path', true) IS DISTINCT FROM 'confirm_transfer' THEN
      RAISE EXCEPTION 'asset_mvp: asset location changes only through confirm_transfer';
    END IF;
    IF NEW.location_revision IS DISTINCT FROM OLD.location_revision + 1 THEN
      RAISE EXCEPTION 'asset_mvp: location_revision must increase by exactly 1';
    END IF;
    IF NEW.current_room_id IS NOT DISTINCT FROM OLD.current_room_id THEN
      RAISE EXCEPTION 'asset_mvp: location_revision cannot change without a room change';
    END IF;
  END IF;
  RETURN NEW;
END;
$fn$;

CREATE TRIGGER assets_before_write
BEFORE INSERT OR UPDATE ON assets
FOR EACH ROW EXECUTE FUNCTION assets_before_write();

CREATE FUNCTION assets_after_insert_audit() RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $fn$
BEGIN
  PERFORM set_config('app.write_path', 'register_asset', true);
  INSERT INTO location_audit_events (
    asset_id,
    transfer_id,
    event_type,
    from_room_id,
    to_room_id,
    location_revision
  ) VALUES (
    NEW.id,
    NULL,
    CASE
      WHEN NEW.current_room_id IS NULL THEN 'registered_unplaced'
      ELSE 'initial_placement'
    END,
    NULL,
    NEW.current_room_id,
    NEW.location_revision
  );
  PERFORM set_config('app.write_path', '', true);
  RETURN NEW;
END;
$fn$;

CREATE TRIGGER assets_after_insert_audit
AFTER INSERT ON assets
FOR EACH ROW EXECUTE FUNCTION assets_after_insert_audit();

CREATE FUNCTION location_audit_events_append_only() RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $fn$
BEGIN
  RAISE EXCEPTION 'asset_mvp: location_audit_events are append-only';
END;
$fn$;

CREATE TRIGGER location_audit_events_append_only
BEFORE UPDATE OR DELETE ON location_audit_events
FOR EACH ROW EXECUTE FUNCTION location_audit_events_append_only();

CREATE FUNCTION location_audit_events_enforce() RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $fn$
DECLARE
  v_path text;
  v_room uuid;
  v_revision bigint;
BEGIN
  v_path := current_setting('app.write_path', true);

  IF v_path IS DISTINCT FROM 'register_asset'
     AND v_path IS DISTINCT FROM 'confirm_transfer' THEN
    RAISE EXCEPTION 'asset_mvp: direct audit inserts are not allowed';
  END IF;

  IF v_path = 'register_asset'
     AND NEW.event_type NOT IN ('initial_placement', 'registered_unplaced') THEN
    RAISE EXCEPTION 'asset_mvp: register_asset cannot write this audit event';
  END IF;
  IF v_path = 'confirm_transfer' AND NEW.event_type IS DISTINCT FROM 'transfer_confirmed' THEN
    RAISE EXCEPTION 'asset_mvp: confirm_transfer cannot write this audit event';
  END IF;

  SELECT current_room_id, location_revision
    INTO v_room, v_revision
  FROM assets
  WHERE id = NEW.asset_id;

  IF NOT FOUND
     OR v_revision IS DISTINCT FROM NEW.location_revision
     OR v_room IS DISTINCT FROM NEW.to_room_id THEN
    RAISE EXCEPTION 'asset_mvp: audit does not match asset location';
  END IF;

  IF NEW.event_type = 'transfer_confirmed' THEN
    PERFORM 1
    FROM transfers t
    WHERE t.id = NEW.transfer_id
      AND t.status = 'confirmed'
      AND t.asset_id = NEW.asset_id
      AND t.from_room_id IS NOT DISTINCT FROM NEW.from_room_id
      AND t.to_room_id IS NOT DISTINCT FROM NEW.to_room_id
      AND t.expected_location_revision = NEW.location_revision - 1;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'asset_mvp: transfer audit does not match a confirmed transfer';
    END IF;
  END IF;

  RETURN NEW;
END;
$fn$;

CREATE TRIGGER location_audit_events_enforce
BEFORE INSERT ON location_audit_events
FOR EACH ROW EXECUTE FUNCTION location_audit_events_enforce();

CREATE FUNCTION transfers_enforce() RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $fn$
DECLARE
  v_path text;
BEGIN
  v_path := current_setting('app.write_path', true);

  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'asset_mvp: transfers are not deleted';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF v_path IS DISTINCT FROM 'initiate_transfer' THEN
      RAISE EXCEPTION 'asset_mvp: transfers are created only by initiate_transfer';
    END IF;
    IF NEW.status IS DISTINCT FROM 'initiated' OR NEW.resolved_at IS NOT NULL THEN
      RAISE EXCEPTION 'asset_mvp: new transfers must be initiated';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.asset_id IS DISTINCT FROM OLD.asset_id
     OR NEW.from_room_id IS DISTINCT FROM OLD.from_room_id
     OR NEW.to_room_id IS DISTINCT FROM OLD.to_room_id
     OR NEW.expected_location_revision IS DISTINCT FROM OLD.expected_location_revision
     OR NEW.initiated_at IS DISTINCT FROM OLD.initiated_at THEN
    RAISE EXCEPTION 'asset_mvp: transfer request fields are immutable';
  END IF;

  IF NEW.status IS NOT DISTINCT FROM OLD.status
     AND NEW.resolved_at IS NOT DISTINCT FROM OLD.resolved_at THEN
    RETURN NEW;
  END IF;

  IF v_path = 'confirm_transfer'
     AND OLD.status = 'initiated'
     AND NEW.status IN ('confirmed', 'conflict') THEN
    RETURN NEW;
  END IF;

  IF v_path = 'cancel_transfer'
     AND OLD.status = 'initiated'
     AND NEW.status = 'cancelled' THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'asset_mvp: illegal transfer transition % -> %', OLD.status, NEW.status;
END;
$fn$;

CREATE TRIGGER transfers_enforce
BEFORE INSERT OR UPDATE OR DELETE ON transfers
FOR EACH ROW EXECUTE FUNCTION transfers_enforce();

CREATE FUNCTION model_versions_immutable() RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $fn$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'asset_mvp: model versions are not deleted in this starter';
  END IF;
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.building_id IS DISTINCT FROM OLD.building_id
     OR NEW.label IS DISTINCT FROM OLD.label
     OR NEW.source_kind IS DISTINCT FROM OLD.source_kind
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'asset_mvp: model versions are immutable';
  END IF;
  RETURN NEW;
END;
$fn$;

CREATE TRIGGER model_versions_immutable
BEFORE UPDATE OR DELETE ON model_versions
FOR EACH ROW EXECUTE FUNCTION model_versions_immutable();

CREATE FUNCTION model_objects_enforce() RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $fn$
DECLARE
  v_source text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'asset_mvp: model objects are not deleted in this starter';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.model_version_id IS DISTINCT FROM OLD.model_version_id
       OR NEW.stable_id IS DISTINCT FROM OLD.stable_id
       OR NEW.stable_id_kind IS DISTINCT FROM OLD.stable_id_kind
       OR NEW.object_role IS DISTINCT FROM OLD.object_role
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'asset_mvp: model object identity is immutable';
    END IF;
    RETURN NEW;
  END IF;

  SELECT source_kind INTO v_source
  FROM model_versions
  WHERE id = NEW.model_version_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'asset_mvp: model_version_not_found';
  END IF;
  IF v_source = 'gltf' AND NEW.stable_id_kind IS DISTINCT FROM 'gltf_extras' THEN
    RAISE EXCEPTION 'asset_mvp: kind_source_mismatch';
  END IF;
  IF v_source = 'ifc' AND NEW.stable_id_kind IS DISTINCT FROM 'ifc_global_id' THEN
    RAISE EXCEPTION 'asset_mvp: kind_source_mismatch';
  END IF;
  RETURN NEW;
END;
$fn$;

CREATE TRIGGER model_objects_enforce
BEFORE INSERT OR UPDATE OR DELETE ON model_objects
FOR EACH ROW EXECUTE FUNCTION model_objects_enforce();

CREATE FUNCTION asset_model_mappings_enforce() RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $fn$
DECLARE
  v_version uuid;
  v_role text;
BEGIN
  SELECT model_version_id, object_role
    INTO v_version, v_role
  FROM model_objects
  WHERE id = NEW.model_object_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'asset_mvp: model_object_not_found';
  END IF;
  IF v_version IS DISTINCT FROM NEW.model_version_id THEN
    RAISE EXCEPTION 'asset_mvp: model object belongs to a different model version';
  END IF;
  IF v_role IS DISTINCT FROM 'asset_anchor' THEN
    RAISE EXCEPTION 'asset_mvp: asset mappings require object_role asset_anchor';
  END IF;
  RETURN NEW;
END;
$fn$;

CREATE TRIGGER asset_model_mappings_enforce
BEFORE INSERT OR UPDATE ON asset_model_mappings
FOR EACH ROW EXECUTE FUNCTION asset_model_mappings_enforce();

CREATE FUNCTION room_model_mappings_enforce() RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $fn$
DECLARE
  v_version uuid;
  v_role text;
  v_model_building uuid;
  v_room_building uuid;
BEGIN
  SELECT model_version_id, object_role
    INTO v_version, v_role
  FROM model_objects
  WHERE id = NEW.model_object_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'asset_mvp: model_object_not_found';
  END IF;
  IF v_version IS DISTINCT FROM NEW.model_version_id THEN
    RAISE EXCEPTION 'asset_mvp: model object belongs to a different model version';
  END IF;
  IF v_role IS DISTINCT FROM 'room' THEN
    RAISE EXCEPTION 'asset_mvp: room mappings require object_role room';
  END IF;

  SELECT building_id INTO v_model_building
  FROM model_versions
  WHERE id = NEW.model_version_id;
  SELECT building_id INTO v_room_building
  FROM rooms
  WHERE id = NEW.room_id;

  IF v_model_building IS NULL OR v_room_building IS NULL THEN
    RAISE EXCEPTION 'asset_mvp: room_not_found';
  END IF;
  IF v_model_building IS DISTINCT FROM v_room_building THEN
    RAISE EXCEPTION 'asset_mvp: room_building_mismatch';
  END IF;
  RETURN NEW;
END;
$fn$;

CREATE TRIGGER room_model_mappings_enforce
BEFORE INSERT OR UPDATE ON room_model_mappings
FOR EACH ROW EXECUTE FUNCTION room_model_mappings_enforce();

CREATE FUNCTION mapping_status_only_update() RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $fn$
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.model_version_id IS DISTINCT FROM OLD.model_version_id
     OR NEW.model_object_id IS DISTINCT FROM OLD.model_object_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'asset_mvp: mapping fields other than status are immutable';
  END IF;

  IF TG_TABLE_NAME = 'asset_model_mappings' THEN
    IF NEW.asset_id IS DISTINCT FROM OLD.asset_id THEN
      RAISE EXCEPTION 'asset_mvp: mapping fields other than status are immutable';
    END IF;
  ELSIF TG_TABLE_NAME = 'room_model_mappings' THEN
    IF NEW.room_id IS DISTINCT FROM OLD.room_id THEN
      RAISE EXCEPTION 'asset_mvp: mapping fields other than status are immutable';
    END IF;
  ELSE
    RAISE EXCEPTION 'asset_mvp: unexpected mapping table %', TG_TABLE_NAME;
  END IF;

  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;
  IF OLD.status = 'proposed' AND NEW.status IN ('accepted', 'rejected') THEN
    RETURN NEW;
  END IF;
  IF OLD.status = 'accepted' THEN
    RAISE EXCEPTION 'asset_mvp: accepted mappings are immutable';
  END IF;
  IF OLD.status = 'rejected' THEN
    RAISE EXCEPTION 'asset_mvp: rejected mappings are immutable';
  END IF;
  RAISE EXCEPTION 'asset_mvp: invalid mapping status';
END;
$fn$;

CREATE TRIGGER asset_model_mappings_status_only
BEFORE UPDATE ON asset_model_mappings
FOR EACH ROW EXECUTE FUNCTION mapping_status_only_update();

CREATE TRIGGER room_model_mappings_status_only
BEFORE UPDATE ON room_model_mappings
FOR EACH ROW EXECUTE FUNCTION mapping_status_only_update();

CREATE FUNCTION mapping_reviews_no_reassignment() RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $fn$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'asset_mvp: mapping reviews are append-only';
  END IF;

  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.model_version_id IS DISTINCT FROM OLD.model_version_id
     OR NEW.review_kind IS DISTINCT FROM OLD.review_kind
     OR NEW.stable_id IS DISTINCT FROM OLD.stable_id
     OR NEW.stable_id_kind IS DISTINCT FROM OLD.stable_id_kind
     OR NEW.model_object_id IS DISTINCT FROM OLD.model_object_id
     OR NEW.room_id IS DISTINCT FROM OLD.room_id
     OR NEW.asset_id IS DISTINCT FROM OLD.asset_id
     OR NEW.detail IS DISTINCT FROM OLD.detail
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'asset_mvp: review subject is immutable';
  END IF;

  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;
  IF OLD.status = 'open' AND NEW.status = 'resolved' THEN
    RETURN NEW;
  END IF;
  IF OLD.status = 'resolved' THEN
    RAISE EXCEPTION 'asset_mvp: resolved reviews cannot be reopened';
  END IF;
  RAISE EXCEPTION 'asset_mvp: invalid review status';
END;
$fn$;

CREATE TRIGGER mapping_reviews_no_reassignment
BEFORE UPDATE OR DELETE ON mapping_reviews
FOR EACH ROW EXECUTE FUNCTION mapping_reviews_no_reassignment();

CREATE FUNCTION location_audit_is_consistent() RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $fn$
  SELECT
    NOT EXISTS (
      SELECT 1
      FROM assets a
      LEFT JOIN (
        SELECT asset_id,
               min(location_revision) AS min_rev,
               max(location_revision) AS max_rev,
               count(*) AS n,
               count(DISTINCT location_revision) AS distinct_n
        FROM location_audit_events
        GROUP BY asset_id
      ) e ON e.asset_id = a.id
      WHERE e.asset_id IS NULL
         OR e.min_rev <> 1
         OR e.max_rev <> a.location_revision
         OR e.n <> a.location_revision
         OR e.distinct_n <> a.location_revision
    )
    AND NOT EXISTS (
      SELECT 1
      FROM assets a
      JOIN LATERAL (
        SELECT to_room_id
        FROM location_audit_events e
        WHERE e.asset_id = a.id
        ORDER BY location_revision DESC
        LIMIT 1
      ) latest ON true
      WHERE latest.to_room_id IS DISTINCT FROM a.current_room_id
    )
    AND NOT EXISTS (
      SELECT 1
      FROM transfers t
      WHERE t.status = 'confirmed'
        AND (
          SELECT count(*)
          FROM location_audit_events e
          WHERE e.transfer_id = t.id
            AND e.event_type = 'transfer_confirmed'
        ) <> 1
    )
    AND NOT EXISTS (
      SELECT 1
      FROM location_audit_events e
      WHERE e.event_type = 'transfer_confirmed'
        AND NOT EXISTS (
          SELECT 1
          FROM transfers t
          WHERE t.id = e.transfer_id
            AND t.status = 'confirmed'
            AND t.asset_id = e.asset_id
            AND t.from_room_id IS NOT DISTINCT FROM e.from_room_id
            AND t.to_room_id IS NOT DISTINCT FROM e.to_room_id
            AND t.expected_location_revision = e.location_revision - 1
        )
    )
    AND NOT EXISTS (
      SELECT 1
      FROM transfers t
      WHERE t.status IN ('initiated', 'conflict', 'cancelled')
        AND EXISTS (
          SELECT 1
          FROM location_audit_events e
          WHERE e.transfer_id = t.id
        )
    );
$fn$;

CREATE FUNCTION register_asset(
  p_asset_tag text,
  p_name text,
  p_current_room_id uuid
) RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $fn$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO assets (asset_tag, name, current_room_id)
  VALUES (p_asset_tag, p_name, p_current_room_id)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$fn$;

CREATE FUNCTION initiate_transfer(p_asset_id uuid, p_to_room_id uuid) RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $fn$
DECLARE
  v_asset assets%ROWTYPE;
  v_id uuid;
BEGIN
  IF p_to_room_id IS NULL THEN
    RAISE EXCEPTION 'asset_mvp: room_required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM rooms WHERE id = p_to_room_id) THEN
    RAISE EXCEPTION 'asset_mvp: room_not_found';
  END IF;

  SELECT * INTO v_asset
  FROM assets
  WHERE id = p_asset_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'asset_mvp: asset_not_found';
  END IF;
  IF v_asset.current_room_id IS NOT DISTINCT FROM p_to_room_id THEN
    RAISE EXCEPTION 'asset_mvp: same_room';
  END IF;

  PERFORM set_config('app.write_path', 'initiate_transfer', true);
  INSERT INTO transfers (
    asset_id,
    from_room_id,
    to_room_id,
    expected_location_revision,
    status
  ) VALUES (
    v_asset.id,
    v_asset.current_room_id,
    p_to_room_id,
    v_asset.location_revision,
    'initiated'
  ) RETURNING id INTO v_id;
  PERFORM set_config('app.write_path', '', true);
  RETURN v_id;
END;
$fn$;

-- Result codes: confirmed, already_confirmed, conflict, already_conflict,
-- cancelled, not_found.
-- confirmed writes the location change and exactly one audit row.
-- conflict writes neither. already_* and cancelled write nothing.
CREATE FUNCTION confirm_transfer(p_transfer_id uuid) RETURNS text
LANGUAGE plpgsql
SET search_path = public
AS $fn$
DECLARE
  v_transfer transfers%ROWTYPE;
  v_asset assets%ROWTYPE;
  v_matches boolean;
BEGIN
  SELECT * INTO v_transfer
  FROM transfers
  WHERE id = p_transfer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN 'not_found';
  END IF;

  IF v_transfer.status = 'confirmed' THEN
    RETURN 'already_confirmed';
  ELSIF v_transfer.status = 'conflict' THEN
    RETURN 'already_conflict';
  ELSIF v_transfer.status = 'cancelled' THEN
    RETURN 'cancelled';
  ELSIF v_transfer.status <> 'initiated' THEN
    RAISE EXCEPTION 'asset_mvp: unexpected transfer status %', v_transfer.status;
  END IF;

  SELECT * INTO v_asset
  FROM assets
  WHERE id = v_transfer.asset_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'asset_mvp: asset_not_found';
  END IF;

  v_matches := v_asset.current_room_id IS NOT DISTINCT FROM v_transfer.from_room_id
    AND v_asset.location_revision = v_transfer.expected_location_revision;

  PERFORM set_config('app.write_path', 'confirm_transfer', true);

  IF v_matches THEN
    UPDATE transfers
       SET status = 'confirmed',
           resolved_at = now()
     WHERE id = v_transfer.id;

    UPDATE assets
       SET current_room_id = v_transfer.to_room_id,
           location_revision = v_asset.location_revision + 1
     WHERE id = v_asset.id;

    INSERT INTO location_audit_events (
      asset_id,
      transfer_id,
      event_type,
      from_room_id,
      to_room_id,
      location_revision
    ) VALUES (
      v_asset.id,
      v_transfer.id,
      'transfer_confirmed',
      v_transfer.from_room_id,
      v_transfer.to_room_id,
      v_asset.location_revision + 1
    );
  ELSE
    UPDATE transfers
       SET status = 'conflict',
           resolved_at = now()
     WHERE id = v_transfer.id;
  END IF;

  PERFORM set_config('app.write_path', '', true);

  IF v_matches THEN
    RETURN 'confirmed';
  END IF;
  RETURN 'conflict';
END;
$fn$;

-- Cancellation does not reverse a confirmed move and does not delete history.
-- A confirmed move is reversed only by a later transfer, which this function
-- does not create.
CREATE FUNCTION cancel_transfer(p_transfer_id uuid) RETURNS text
LANGUAGE plpgsql
SET search_path = public
AS $fn$
DECLARE
  v_transfer transfers%ROWTYPE;
BEGIN
  SELECT * INTO v_transfer
  FROM transfers
  WHERE id = p_transfer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN 'not_found';
  END IF;
  IF v_transfer.status = 'cancelled' THEN
    RETURN 'already_cancelled';
  ELSIF v_transfer.status = 'confirmed' THEN
    RETURN 'confirmed_irreversible';
  ELSIF v_transfer.status = 'conflict' THEN
    RETURN 'conflict_terminal';
  END IF;

  PERFORM set_config('app.write_path', 'cancel_transfer', true);
  UPDATE transfers
     SET status = 'cancelled',
         resolved_at = now()
   WHERE id = v_transfer.id;
  PERFORM set_config('app.write_path', '', true);
  RETURN 'cancelled';
END;
$fn$;

CREATE FUNCTION register_model_object(
  p_model_version_id uuid,
  p_stable_id text,
  p_stable_id_kind text,
  p_object_role text
) RETURNS TABLE (outcome text, model_object_id uuid, review_id uuid)
LANGUAGE plpgsql
SET search_path = public
AS $fn$
DECLARE
  v_source text;
  v_existing uuid;
  v_review uuid;
  v_object uuid;
  v_trimmed text;
BEGIN
  SELECT source_kind INTO v_source
  FROM model_versions
  WHERE id = p_model_version_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'asset_mvp: model_version_not_found';
  END IF;
  IF p_stable_id_kind IS NULL
     OR p_stable_id_kind NOT IN ('gltf_extras', 'ifc_global_id') THEN
    RAISE EXCEPTION 'asset_mvp: invalid_stable_id_kind';
  END IF;
  IF p_object_role IS NULL OR p_object_role NOT IN ('room', 'asset_anchor') THEN
    RAISE EXCEPTION 'asset_mvp: invalid_role';
  END IF;
  IF (v_source = 'gltf' AND p_stable_id_kind <> 'gltf_extras')
     OR (v_source = 'ifc' AND p_stable_id_kind <> 'ifc_global_id') THEN
    RAISE EXCEPTION 'asset_mvp: kind_source_mismatch';
  END IF;

  v_trimmed := btrim(coalesce(p_stable_id, ''));
  IF p_stable_id IS NULL
     OR v_trimmed = ''
     OR p_stable_id <> v_trimmed
     OR length(v_trimmed) > 128 THEN
    INSERT INTO mapping_reviews (
      model_version_id, review_kind, stable_id_kind, detail
    ) VALUES (
      p_model_version_id,
      'missing_stable_id',
      p_stable_id_kind,
      'stable id is missing, blank, untrimmed, or longer than 128 characters; no model object was created'
    ) RETURNING id INTO v_review;
    outcome := 'needs_review';
    model_object_id := NULL;
    review_id := v_review;
    RETURN NEXT;
    RETURN;
  END IF;

  IF (
       p_stable_id_kind = 'gltf_extras' AND v_trimmed ~ '^[0-9]+$'
     ) OR (
       p_stable_id_kind = 'ifc_global_id'
       AND v_trimmed !~ '^[0-9A-Za-z_$]{22}$'
     ) THEN
    INSERT INTO mapping_reviews (
      model_version_id, review_kind, stable_id, stable_id_kind, detail
    ) VALUES (
      p_model_version_id,
      'rejected_unstable_id',
      left(v_trimmed, 128),
      p_stable_id_kind,
      'identifier is a bare integer or not a 22-character IFC GlobalId; no model object was created'
    ) RETURNING id INTO v_review;
    outcome := 'needs_review';
    model_object_id := NULL;
    review_id := v_review;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT id INTO v_existing
  FROM model_objects
  WHERE model_version_id = p_model_version_id
    AND stable_id_kind = p_stable_id_kind
    AND stable_id = v_trimmed
  FOR UPDATE;

  IF FOUND THEN
    INSERT INTO mapping_reviews (
      model_version_id,
      review_kind,
      stable_id,
      stable_id_kind,
      model_object_id,
      detail
    ) VALUES (
      p_model_version_id,
      'duplicate_stable_id',
      v_trimmed,
      p_stable_id_kind,
      v_existing,
      'stable id already registered for this model version; existing object was left unchanged'
    ) RETURNING id INTO v_review;
    outcome := 'needs_review';
    model_object_id := v_existing;
    review_id := v_review;
    RETURN NEXT;
    RETURN;
  END IF;

  BEGIN
    INSERT INTO model_objects (
      model_version_id, stable_id, stable_id_kind, object_role
    ) VALUES (
      p_model_version_id, v_trimmed, p_stable_id_kind, p_object_role
    ) RETURNING id INTO v_object;
  EXCEPTION
    WHEN unique_violation THEN
      SELECT id INTO v_existing
      FROM model_objects
      WHERE model_version_id = p_model_version_id
        AND stable_id_kind = p_stable_id_kind
        AND stable_id = v_trimmed;
      INSERT INTO mapping_reviews (
        model_version_id,
        review_kind,
        stable_id,
        stable_id_kind,
        model_object_id,
        detail
      ) VALUES (
        p_model_version_id,
        'duplicate_stable_id',
        v_trimmed,
        p_stable_id_kind,
        v_existing,
        'stable id already registered for this model version; existing object was left unchanged'
      ) RETURNING id INTO v_review;
      outcome := 'needs_review';
      model_object_id := v_existing;
      review_id := v_review;
      RETURN NEXT;
      RETURN;
  END;

  outcome := 'registered';
  model_object_id := v_object;
  review_id := NULL;
  RETURN NEXT;
END;
$fn$;

CREATE FUNCTION propose_asset_mapping(
  p_model_version_id uuid,
  p_model_object_id uuid,
  p_asset_id uuid
) RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $fn$
DECLARE
  v_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM assets WHERE id = p_asset_id) THEN
    RAISE EXCEPTION 'asset_mvp: asset_not_found';
  END IF;
  INSERT INTO asset_model_mappings (
    model_version_id, model_object_id, asset_id, status
  ) VALUES (
    p_model_version_id, p_model_object_id, p_asset_id, 'proposed'
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$fn$;

CREATE FUNCTION accept_asset_mapping(p_mapping_id uuid) RETURNS text
LANGUAGE plpgsql
SET search_path = public
AS $fn$
DECLARE
  v_status text;
BEGIN
  SELECT status INTO v_status
  FROM asset_model_mappings
  WHERE id = p_mapping_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN 'not_found';
  END IF;
  IF v_status = 'accepted' THEN
    RETURN 'already_accepted';
  END IF;
  IF v_status = 'rejected' THEN
    RETURN 'rejected';
  END IF;
  UPDATE asset_model_mappings
     SET status = 'accepted'
   WHERE id = p_mapping_id;
  RETURN 'accepted';
END;
$fn$;

CREATE FUNCTION propose_room_mapping(
  p_model_version_id uuid,
  p_model_object_id uuid,
  p_room_id uuid
) RETURNS TABLE (outcome text, mapping_id uuid, review_id uuid)
LANGUAGE plpgsql
SET search_path = public
AS $fn$
DECLARE
  v_object_version uuid;
  v_role text;
  v_model_building uuid;
  v_room_building uuid;
  v_mapping uuid;
  v_review uuid;
BEGIN
  SELECT model_version_id, object_role
    INTO v_object_version, v_role
  FROM model_objects
  WHERE id = p_model_object_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'asset_mvp: model_object_not_found';
  END IF;
  IF v_object_version IS DISTINCT FROM p_model_version_id THEN
    RAISE EXCEPTION 'asset_mvp: model object belongs to a different model version';
  END IF;
  IF v_role IS DISTINCT FROM 'room' THEN
    RAISE EXCEPTION 'asset_mvp: room mappings require object_role room';
  END IF;

  SELECT building_id INTO v_model_building
  FROM model_versions
  WHERE id = p_model_version_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'asset_mvp: model_version_not_found';
  END IF;
  SELECT building_id INTO v_room_building
  FROM rooms
  WHERE id = p_room_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'asset_mvp: room_not_found';
  END IF;

  IF v_model_building IS DISTINCT FROM v_room_building THEN
    INSERT INTO mapping_reviews (
      model_version_id, review_kind, model_object_id, room_id, detail
    ) VALUES (
      p_model_version_id,
      'room_building_mismatch',
      p_model_object_id,
      p_room_id,
      'model version and room belong to different buildings; no mapping row was written and no asset was moved'
    ) RETURNING id INTO v_review;
    outcome := 'needs_review';
    mapping_id := NULL;
    review_id := v_review;
    RETURN NEXT;
    RETURN;
  END IF;

  INSERT INTO room_model_mappings (
    model_version_id, model_object_id, room_id, status
  ) VALUES (
    p_model_version_id, p_model_object_id, p_room_id, 'proposed'
  ) RETURNING id INTO v_mapping;
  outcome := 'proposed';
  mapping_id := v_mapping;
  review_id := NULL;
  RETURN NEXT;
END;
$fn$;

CREATE FUNCTION accept_room_mapping(p_mapping_id uuid) RETURNS text
LANGUAGE plpgsql
SET search_path = public
AS $fn$
DECLARE
  v_status text;
BEGIN
  SELECT status INTO v_status
  FROM room_model_mappings
  WHERE id = p_mapping_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN 'not_found';
  END IF;
  IF v_status = 'accepted' THEN
    RETURN 'already_accepted';
  END IF;
  IF v_status = 'rejected' THEN
    RETURN 'rejected';
  END IF;
  UPDATE room_model_mappings
     SET status = 'accepted'
   WHERE id = p_mapping_id;
  RETURN 'accepted';
END;
$fn$;

CREATE FUNCTION flag_custody_room_mismatch(
  p_asset_id uuid,
  p_model_version_id uuid,
  p_observed_room_id uuid,
  p_detail text
) RETURNS TABLE (outcome text, review_id uuid)
LANGUAGE plpgsql
SET search_path = public
AS $fn$
DECLARE
  v_current uuid;
  v_review uuid;
BEGIN
  IF p_detail IS NULL OR btrim(p_detail) = '' THEN
    RAISE EXCEPTION 'asset_mvp: detail_required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM model_versions WHERE id = p_model_version_id) THEN
    RAISE EXCEPTION 'asset_mvp: model_version_not_found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM rooms WHERE id = p_observed_room_id) THEN
    RAISE EXCEPTION 'asset_mvp: room_not_found';
  END IF;

  SELECT current_room_id INTO v_current
  FROM assets
  WHERE id = p_asset_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'asset_mvp: asset_not_found';
  END IF;

  IF v_current IS NOT DISTINCT FROM p_observed_room_id THEN
    outcome := 'no_mismatch';
    review_id := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  INSERT INTO mapping_reviews (
    model_version_id, review_kind, asset_id, room_id, detail
  ) VALUES (
    p_model_version_id,
    'custody_room_mismatch',
    p_asset_id,
    p_observed_room_id,
    btrim(p_detail)
  ) RETURNING id INTO v_review;
  outcome := 'needs_review';
  review_id := v_review;
  RETURN NEXT;
END;
$fn$;

CREATE FUNCTION open_unmatched_object_review(p_model_object_id uuid)
RETURNS TABLE (outcome text, review_id uuid)
LANGUAGE plpgsql
SET search_path = public
AS $fn$
DECLARE
  v_version uuid;
  v_existing uuid;
  v_review uuid;
BEGIN
  SELECT model_version_id INTO v_version
  FROM model_objects
  WHERE id = p_model_object_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'asset_mvp: model_object_not_found';
  END IF;

  IF EXISTS (
    SELECT 1 FROM asset_model_mappings
    WHERE model_object_id = p_model_object_id AND status = 'accepted'
  ) OR EXISTS (
    SELECT 1 FROM room_model_mappings
    WHERE model_object_id = p_model_object_id AND status = 'accepted'
  ) THEN
    outcome := 'already_mapped';
    review_id := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT id INTO v_existing
  FROM mapping_reviews
  WHERE model_object_id = p_model_object_id
    AND review_kind = 'unmatched_model_object'
    AND status = 'open'
  LIMIT 1;
  IF FOUND THEN
    outcome := 'already_open';
    review_id := v_existing;
    RETURN NEXT;
    RETURN;
  END IF;

  BEGIN
    INSERT INTO mapping_reviews (
      model_version_id, review_kind, model_object_id, detail
    ) VALUES (
      v_version,
      'unmatched_model_object',
      p_model_object_id,
      'model object has no accepted asset or room mapping; no assignment was created'
    ) RETURNING id INTO v_review;
  EXCEPTION
    WHEN unique_violation THEN
      SELECT id INTO v_review
      FROM mapping_reviews
      WHERE model_object_id = p_model_object_id
        AND review_kind = 'unmatched_model_object'
        AND status = 'open'
      LIMIT 1;
      outcome := 'already_open';
      review_id := v_review;
      RETURN NEXT;
      RETURN;
  END;

  outcome := 'opened';
  review_id := v_review;
  RETURN NEXT;
END;
$fn$;

COMMENT ON TABLE assets IS
  'Custody records. id and asset_tag are immutable and are not rendering identifiers.';
COMMENT ON COLUMN assets.id IS
  'Database-assigned custody UUID. Independent of glTF extras, IFC GlobalId, and Three.js runtime UUIDs.';
COMMENT ON COLUMN assets.current_room_id IS
  'Last confirmed custody room. Null means no room has been recorded. Not a sensor reading.';
COMMENT ON TABLE location_audit_events IS
  'Append-only custody history. Physical movement is not inferred from 3D files or from Three.js.';
COMMENT ON TABLE model_objects IS
  'Authored model identity for one model version. stable_id is a glTF extras value or an IFC GlobalId. Three.js runtime UUIDs and node indexes are not stored.';
COMMENT ON TABLE mapping_reviews IS
  'Open questions. Changing status to resolved does not assign an asset or move a room.';
COMMENT ON FUNCTION confirm_transfer(uuid) IS
  'Atomically confirms one initiated transfer, or records a conflict without moving the asset. Repeat calls are idempotent.';
-- Starter-scale commit check. It runs once per affected row at COMMIT and
-- scans custody history. SET CONSTRAINTS ... IMMEDIATE is not a supported
-- way to call confirm_transfer, because the function writes the asset before
-- the audit row.
CREATE FUNCTION location_audit_commit_check() RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $fn$
BEGIN
  IF NOT location_audit_is_consistent() THEN
    RAISE EXCEPTION 'asset_mvp: location audit is inconsistent at commit';
  END IF;
  RETURN NULL;
END;
$fn$;

CREATE CONSTRAINT TRIGGER assets_location_audit_commit_check
AFTER INSERT OR UPDATE OR DELETE ON assets
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION location_audit_commit_check();

CREATE CONSTRAINT TRIGGER transfers_location_audit_commit_check
AFTER INSERT OR UPDATE OR DELETE ON transfers
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION location_audit_commit_check();

CREATE CONSTRAINT TRIGGER location_audit_events_commit_check
AFTER INSERT OR UPDATE OR DELETE ON location_audit_events
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION location_audit_commit_check();

COMMENT ON FUNCTION location_audit_is_consistent() IS
  'True when every asset revision matches its audit rows and every confirmed transfer has exactly one audit row.';

COMMIT;
