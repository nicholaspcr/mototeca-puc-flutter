-- Mototeca initial schema
-- Apply with: npm run migrate  (wraps `psql "$DATABASE_URL" -f db/migrations/0001_init.sql`)

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE owners (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone TEXT NOT NULL UNIQUE,
  cpf_hash TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE workshops (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cnpj TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  address TEXT,
  verified BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE mechanics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workshop_id UUID NOT NULL REFERENCES workshops(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'mechanic',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE vehicles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plate TEXT NOT NULL UNIQUE,
  chassi TEXT NOT NULL UNIQUE,
  make TEXT NOT NULL,
  model TEXT NOT NULL,
  year INTEGER NOT NULL,
  current_owner_id UUID REFERENCES owners(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_vehicles_plate ON vehicles(plate);

CREATE TYPE service_type AS ENUM (
  'oil_change',
  'scheduled_review',
  'brakes',
  'chain_and_sprocket',
  'tires',
  'electrical',
  'spark_plugs',
  'suspension',
  'clutch',
  'fuel_injection',
  'bodywork',
  'other'
);

-- Append-only by convention: a workshop never updates another shop's row.
-- Corrections are new rows that point back via superseded_by, which is what
-- keeps cross-workshop history trustworthy (see ARCHITECTURE.md section 4).
CREATE TABLE service_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id UUID NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
  workshop_id UUID NOT NULL REFERENCES workshops(id) ON DELETE RESTRICT,
  mechanic_id UUID REFERENCES mechanics(id) ON DELETE SET NULL,
  type service_type NOT NULL,
  mileage_km INTEGER NOT NULL,
  cost_cents INTEGER,
  notes TEXT,
  superseded_by UUID REFERENCES service_records(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_service_records_vehicle_id ON service_records(vehicle_id);

CREATE TABLE parts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_record_id UUID NOT NULL REFERENCES service_records(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  quantity INTEGER NOT NULL DEFAULT 1,
  cost_cents INTEGER
);

CREATE TABLE attachments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_record_id UUID NOT NULL REFERENCES service_records(id) ON DELETE CASCADE,
  url TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('photo', 'invoice')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
