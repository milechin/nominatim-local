#!/bin/bash
# =============================================================================
# Nominatim Container Entrypoint
# =============================================================================
# Handles the full startup sequence:
#   1. Initialize PostgreSQL data directory (first run only)
#   2. Start PostgreSQL
#   3. First-run setup (create DB users, run OSM import)
#   4. Start the Nominatim API server
#
# Environment variables (set in docker-compose.yml):
#   OSM_FILE      - filename of the .osm.pbf file in /data (required on first run)
#   NOMINATIM_DIR - nominatim project directory (default: /home/nominatim/nominatim-project)
# =============================================================================

set -e  # Exit immediately on any error

export PATH=/usr/pgsql-17/bin:$PATH

OSM_FILE="${OSM_FILE:-}"
NOMINATIM_DIR="${NOMINATIM_DIR:-/home/nominatim/nominatim-project}"
PG_DATA="/var/lib/pgsql/17/data"
PG_LOG="/var/log/postgresql/postgresql.log"

# -----------------------------------------------------------------------------
# Step 1 — Initialize PostgreSQL data directory (first run only)
# -----------------------------------------------------------------------------
# initdb is intentionally run here at container startup, not during the Docker
# build. Running initdb during build and then mounting a volume over the data
# directory causes subtle PostgreSQL/PostGIS compatibility issues that break
# the Nominatim import. Running it at runtime ensures the cluster is always
# initialized fresh against the live mounted volume.
if [ ! -f "$PG_DATA/PG_VERSION" ]; then
  echo ">>> Initializing PostgreSQL data directory..."
  sudo -u postgres /usr/pgsql-17/bin/initdb --locale=C.UTF-8 --encoding=UTF8 -D "$PG_DATA"

  echo ">>> Configuring PostgreSQL for local trust connections..."
  sudo -u postgres sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" \
    "$PG_DATA/postgresql.conf"
  printf "local   all   all                trust\n"  | sudo -u postgres tee    "$PG_DATA/pg_hba.conf"
  printf "host    all   all  127.0.0.1/32  trust\n"  | sudo -u postgres tee -a "$PG_DATA/pg_hba.conf"
  printf "host    all   all  ::1/128       trust\n"  | sudo -u postgres tee -a "$PG_DATA/pg_hba.conf"
else
  echo ">>> PostgreSQL data directory already initialized, skipping initdb."
fi

# -----------------------------------------------------------------------------
# Step 2 — Start PostgreSQL
# -----------------------------------------------------------------------------
echo ">>> Starting PostgreSQL..."
sudo -u postgres /usr/pgsql-17/bin/pg_ctl -D "$PG_DATA" -l "$PG_LOG" start

# Wait until PostgreSQL is accepting connections
echo ">>> Waiting for PostgreSQL to be ready..."
for i in $(seq 1 30); do
  if sudo -u postgres /usr/pgsql-17/bin/pg_isready -q; then
    echo ">>> PostgreSQL is ready."
    break
  fi
  echo "    Attempt $i/30 — not ready yet, waiting..."
  sleep 2
done

if ! sudo -u postgres /usr/pgsql-17/bin/pg_isready -q; then
  echo "ERROR: PostgreSQL did not become ready in time. Check $PG_LOG"
  exit 1
fi

# -----------------------------------------------------------------------------
# Step 3 — First-run setup: create required DB users
# -----------------------------------------------------------------------------
# Two roles are required before import:
#   nominatim — superuser used by the import process and API
#   www-data  — role expected by Nominatim internals (no superuser needed)
# Both must be created as the postgres superuser (chicken-and-egg: the
# nominatim role doesn't exist yet when this script first runs).
if ! psql -U postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='nominatim'" | grep -q 1; then
  echo ">>> First run detected: creating nominatim PostgreSQL user..."
  sudo -u postgres createuser -s nominatim
else
  echo ">>> nominatim PostgreSQL user already exists, skipping creation."
fi

if ! psql -U postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='www-data'" | grep -q 1; then
  echo ">>> Creating www-data PostgreSQL role..."
  sudo -u postgres createuser www-data
else
  echo ">>> www-data PostgreSQL role already exists, skipping creation."
fi

# -----------------------------------------------------------------------------
# Step 4 — First-run setup: import OSM data
# -----------------------------------------------------------------------------
# Check whether the nominatim database already exists (i.e. import was done).
if ! psql -U nominatim -lqt | cut -d\| -f1 | grep -qw nominatim; then
  echo ">>> Nominatim database not found — starting OSM import..."

  if [ -z "$OSM_FILE" ]; then
    echo "ERROR: OSM_FILE environment variable is not set."
    echo "       Set it in docker-compose.yml to the filename of your .osm.pbf file in /data/"
    echo "       Example: OSM_FILE=massachusetts-latest.osm.pbf"
    exit 1
  fi

  if [ ! -f "/data/$OSM_FILE" ]; then
    echo "ERROR: OSM file not found at /data/$OSM_FILE"
    echo "       Place your .osm.pbf file in the data/ folder next to docker-compose.yml."
    exit 1
  fi

  echo ">>> Creating Nominatim project directory: $NOMINATIM_DIR"
  sudo mkdir -p "$NOMINATIM_DIR"
  sudo chown nominatim:nominatim "$NOMINATIM_DIR"
  cd "$NOMINATIM_DIR"

  echo ">>> Importing /data/$OSM_FILE — this may take a while..."
  echo "    (Massachusetts ~15-30 min | US Northeast ~2-4 hrs | North America ~24+ hrs)"
  nominatim import --osm-file "/data/$OSM_FILE" 2>&1 | tee "$NOMINATIM_DIR/import.log"

  echo ">>> Import complete."
else
  echo ">>> Nominatim database already exists, skipping import."
fi

# -----------------------------------------------------------------------------
# Step 5 — Start the Nominatim API server
# -----------------------------------------------------------------------------
echo ">>> Starting Nominatim API server on port 8088..."
cd "$NOMINATIM_DIR"
exec nominatim serve --server 0.0.0.0:8088
