#!/bin/sh
# Applies the db/migrations/*.sql files that have not run yet, recording each
# in schema_migrations so running it again is a no-op.
set -eu

: "${DATABASE_URL:?DATABASE_URL is required}"
dir=${MIGRATIONS_DIR:-db/migrations}

run_psql() { PGOPTIONS='-c client_min_messages=warning' psql "$DATABASE_URL" -X -q -v ON_ERROR_STOP=1 "$@"; }

# Tables without a tracking table mean the schema came from the old
# apply-everything loop, and there is no telling which files ran.
untracked=$(run_psql -tA -c "SELECT to_regclass('public.schema_migrations') IS NULL
                               AND to_regclass('public.workshops') IS NOT NULL")
if [ "$untracked" = "t" ]; then
  echo "database predates migration tracking; recreate it with: docker compose down -v" >&2
  exit 1
fi

run_psql -c "CREATE TABLE IF NOT EXISTS schema_migrations (
  version TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
)"

for file in "$dir"/*.sql; do
  version=$(basename "$file" .sql)
  applied=$(echo "SELECT 1 FROM schema_migrations WHERE version = :'version'" |
    run_psql -tA -v version="$version")
  [ -n "$applied" ] && continue

  echo "applying $version"
  run_psql -f "$file"
  echo "INSERT INTO schema_migrations (version) VALUES (:'version')" |
    run_psql -v version="$version"
done

echo "migrations up to date"
