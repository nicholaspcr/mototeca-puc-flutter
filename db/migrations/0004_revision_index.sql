-- Mototeca migration 0004 — supports the append-only correction flow.
--
-- 0001 added service_records.superseded_by but nothing wrote it. Listing now
-- filters superseded rows out, so both list queries need it indexed.

BEGIN;

CREATE INDEX idx_service_records_vehicle_current
  ON service_records(vehicle_id, created_at DESC)
  WHERE superseded_by IS NULL;

CREATE INDEX idx_service_records_workshop_current
  ON service_records(workshop_id, created_at DESC)
  WHERE superseded_by IS NULL;

-- A record can only replace one predecessor.
CREATE UNIQUE INDEX idx_service_records_superseded_by
  ON service_records(superseded_by)
  WHERE superseded_by IS NOT NULL;

COMMIT;
