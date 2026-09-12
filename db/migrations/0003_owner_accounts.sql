-- Mototeca migration 0003 — gives owners (proprietários) an account.
--
-- 0001 modelled an owner as a record someone else creates, with a mandatory
-- CPF. Signing in needs a credential of their own, and a CPF is more personal
-- data than reading your own history warrants (ARCHITECTURE.md §8).

BEGIN;

-- CPF stays available for the ownership-claim flow, but is not required.
ALTER TABLE owners ALTER COLUMN cpf_hash DROP NOT NULL;

-- bcrypt digest. Nullable: a workshop may create an owner row before that
-- person ever signs up.
ALTER TABLE owners ADD COLUMN password_hash TEXT;

-- "Minhas Motos" reads every vehicle of one owner; 0001 had no index.
CREATE INDEX idx_vehicles_current_owner_id ON vehicles(current_owner_id);

COMMIT;
