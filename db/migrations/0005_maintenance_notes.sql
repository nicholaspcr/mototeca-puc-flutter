-- Mototeca migration 0005 — owners publish their own maintenance notes.
--
-- A note joins the plate's public history next to the workshop records, but
-- in its own table: no shop vouches for it, so it never feeds the odometer
-- check or the oil-change reminder.

BEGIN;

CREATE TABLE maintenance_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id UUID NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
  -- The note outlives its author's account, like a record outlives a shop.
  owner_id UUID REFERENCES owners(id) ON DELETE SET NULL,
  -- Chosen by the device, so a retried upload finds the note it already sent.
  client_id UUID NOT NULL,
  done_on DATE NOT NULL,
  description TEXT NOT NULL,
  mileage_km INTEGER,
  cost_cents INTEGER,
  photo_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (owner_id, client_id)
);

CREATE INDEX idx_maintenance_notes_vehicle
  ON maintenance_notes(vehicle_id, done_on DESC, created_at DESC);

COMMIT;
