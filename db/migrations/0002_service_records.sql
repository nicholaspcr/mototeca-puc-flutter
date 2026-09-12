-- Mototeca migration 0002 — makes the schema match the screens in design/.
--
-- Three gaps this closes:
--   1. A service record carries SEVERAL operations (the Novo Registro screen
--      lets the mechanic tick more than one), but 0001 modelled a single
--      `type` column. Moved to a join table.
--   2. Photos are "antes"/"depois", which `attachments.kind` could not express
--      (it only separates a photo from an invoice).
--   3. Workshops had no credential, so there was nothing for the login screen
--      to authenticate against.

BEGIN;

-- 1. Several operations per service record ------------------------------------

CREATE TABLE service_record_operations (
  service_record_id UUID NOT NULL REFERENCES service_records(id) ON DELETE CASCADE,
  type service_type NOT NULL,
  PRIMARY KEY (service_record_id, type)
);

-- Carry the existing single type over before dropping the column.
INSERT INTO service_record_operations (service_record_id, type)
SELECT id, type FROM service_records;

ALTER TABLE service_records DROP COLUMN type;

-- The dashboard lists "this shop's recent records", which 0001 had no index for.
CREATE INDEX idx_service_records_workshop_id ON service_records(workshop_id, created_at DESC);

-- 2. Before/after photos -------------------------------------------------------

-- NULL for invoices, which have no phase.
ALTER TABLE attachments ADD COLUMN phase TEXT CHECK (phase IN ('before', 'after'));
ALTER TABLE attachments ADD CONSTRAINT attachments_phase_only_on_photos
  CHECK (phase IS NULL OR kind = 'photo');

-- 3. Workshop credentials ------------------------------------------------------

-- bcrypt digest; never the password itself. Nullable so the column can be
-- added to rows that predate login, but every new workshop sets it.
ALTER TABLE workshops ADD COLUMN password_hash TEXT;

COMMIT;
