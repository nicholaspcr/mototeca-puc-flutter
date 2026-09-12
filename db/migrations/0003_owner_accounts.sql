-- Mototeca migration 0003 — gives owners (proprietários) an account.
--
-- 0001 modelled an owner as a record someone else creates, with a mandatory
-- CPF. To sign in from the app they need a credential of their own, and asking
-- for a CPF just to see your own bike's history is more personal data than the
-- feature needs (ARCHITECTURE.md section 8 — minimize collection).

BEGIN;

-- Registration is name + phone + password. CPF stays available for the
-- ownership-claim flow later, but is no longer required to hold an account.
ALTER TABLE owners ALTER COLUMN cpf_hash DROP NOT NULL;

-- bcrypt digest, never the password. Nullable so owner rows created by a
-- workshop (before that person ever signs up) remain valid.
ALTER TABLE owners ADD COLUMN password_hash TEXT;

-- "Minhas Motos" reads every vehicle belonging to one owner, which 0001 had
-- no index for.
CREATE INDEX idx_vehicles_current_owner_id ON vehicles(current_owner_id);

COMMIT;
