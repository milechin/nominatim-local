# Nominatim Setup Guide

**Environment:** AlmaLinux 9 Docker container  
**Nominatim version:** 4.x (installed via pip)  
**PostgreSQL:** 17 (PGDG)  
**PostGIS:** 3.3  
**Python:** 3.11  

---

## Running the Container

### Option A — Manual (Dockerfile only)

```bash
# Build the image
docker build -t nominatim:local .

# Run the container
# Note: --name is the container name (no colons); nominatim:local is the image name:tag
docker run -it --name nominatim \
  -p 8088:8088 \
  -p 5432:5432 \
  -v nominatim-data:/data \
  -v nominatim-pgdata:/var/lib/pgsql/17/data \
  nominatim:local /bin/bash
```

You will land inside the container at `/home/nominatim`. Follow Steps 1–7 below manually.

### Option B — Docker Compose (automated)

```bash
docker compose up --build
```

Docker Compose runs `entrypoint.sh` which automates Steps 1–6 below.
See `docker-compose.yml` for configuration options (OSM file, ports, volumes).

### Option C — VSCode Dev Container

Open the `nominatim/` folder in VSCode. When prompted, click **Reopen in Container**.
VSCode will build the image and connect you inside the container automatically.
Follow Steps 1–7 below manually from the VSCode integrated terminal.

---

## Step 1 — Verify PostgreSQL PATH

```bash
export PATH=/usr/pgsql-17/bin:$PATH

# Verify pg_ctl is found
which pg_ctl
pg_ctl --version
```

Add this to your session permanently if needed:
```bash
echo 'export PATH=/usr/pgsql-17/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

---

## Step 2 — Start PostgreSQL

PostgreSQL does not start automatically in the container. Start it manually:

```bash
sudo -u postgres pg_ctl \
  -D /var/lib/pgsql/17/data \
  -l /var/log/postgresql/postgresql.log \
  start

# Verify it is running
sudo -u postgres pg_ctl -D /var/lib/pgsql/17/data status
```

---

## Step 3 — Create PostgreSQL Users

Two roles are required before import:
- `nominatim` — superuser used by the import process and API
- `www-data` — role expected by Nominatim internals (no superuser needed)

> **Important:** You must run `createuser` as `sudo -u postgres`, not as the `nominatim`
> Linux user, because the `nominatim` PostgreSQL role doesn't exist yet (chicken-and-egg).

```bash
# Create the nominatim superuser (matches the container's Linux user)
sudo -u postgres createuser -s nominatim

# Create the www-data role (required by Nominatim — import will fail without it)
sudo -u postgres createuser www-data

# Verify both roles exist
psql -U nominatim -c "\du"
```

---

## Step 4 — Verify Nominatim Installation

```bash
nominatim --version
```

If the command is not found, install it:
```bash
# Note: PyPI package is 'osmium', not 'pyosmium'
python3.11 -m pip install nominatim-db nominatim-api uvicorn falcon osmium
```

---

## Step 5 — Download OSM Data

> **⚠ Do this before going offline.** OSM extract files must be downloaded while internet access is available.

### Docker Compose path (Option B)

Create a `data/` folder next to `docker-compose.yml` and download the OSM extract into it.
Docker Compose bind-mounts this folder into the container at `/data`.

```bash
# From the nominatim/ directory (where docker-compose.yml lives)
mkdir -p data

# Option A: Massachusetts only (~300 MB, good for testing)
wget -O data/massachusetts-latest.osm.pbf \
  https://download.geofabrik.de/north-america/us/massachusetts-latest.osm.pbf

# Option B: Full US Northeast (~1 GB)
# wget -O data/us-northeast-latest.osm.pbf \
#   https://download.geofabrik.de/north-america/us-northeast-latest.osm.pbf

# Option C: Full North America (~12 GB)
# wget -O data/north-america-latest.osm.pbf \
#   https://download.geofabrik.de/north-america-latest.osm.pbf

# Verify the download
ls -lh data/*.osm.pbf
```

Then set `OSM_FILE` in `docker-compose.yml` to match the filename (e.g. `massachusetts-latest.osm.pbf`).

### Manual path (Option A)

If running the container manually with `docker run`, download the file inside the container:

```bash
# Inside the container
wget -O /data/massachusetts-latest.osm.pbf \
  https://download.geofabrik.de/north-america/us/massachusetts-latest.osm.pbf
```

Browse all available extracts at: https://download.geofabrik.de/

---

## Step 6 — Import OSM Data

```bash
cd ~/nominatim-project

# Import — runtime varies by region size:
#   Massachusetts:  ~15-30 minutes
#   US Northeast:   ~2-4 hours
#   North America:  ~24+ hours
nominatim import --osm-file /data/massachusetts-latest.osm.pbf 2>&1 | tee import.log

# Monitor progress in a second terminal:
# tail -f ~/nominatim-project/import.log
```

---

## Step 7 — Start the API Server

```bash
cd ~/nominatim-project

# Start the API server (port 8088)
# Note: uses --server host:port, not --address/--port flags
nominatim serve --server 0.0.0.0:8088
```

Leave this terminal running. Open a second terminal for testing.

---

## Step 8 — Test the API

```bash
# Forward geocoding: address → coordinates
curl "http://localhost:8088/search?q=Kenmore+Square+Boston+MA&format=json&limit=1" \
  | python3 -m json.tool

# Forward geocoding with structured parameters
curl "http://localhost:8088/search?street=77+Massachusetts+Ave&city=Cambridge&state=MA&country=US&format=json" \
  | python3 -m json.tool

# Reverse geocoding: coordinates → address
curl "http://localhost:8088/reverse?lat=42.3601&lon=-71.0942&format=json" \
  | python3 -m json.tool

# Lookup by OSM ID
curl "http://localhost:8088/lookup?osm_ids=R1804325&format=json" \
  | python3 -m json.tool
```

---

## Step 9 — API Response Fields

A successful search response looks like:

```json
[
  {
    "place_id": 123456,
    "display_name": "Kenmore Square, Boston, Suffolk County, Massachusetts, United States",
    "lat": "42.348596",
    "lon": "-71.094938",
    "type": "neighbourhood",
    "importance": 0.6
  }
]
```

---

## Useful Commands

```bash
# Check PostgreSQL status
sudo -u postgres pg_ctl -D /var/lib/pgsql/17/data status

# Stop PostgreSQL
sudo -u postgres pg_ctl -D /var/lib/pgsql/17/data stop

# Connect to the Nominatim database directly
psql -U nominatim -d nominatim

# Check database size
psql -U nominatim -d nominatim -c "\l+"

# Rebuild search index only (if import was interrupted)
cd ~/nominatim-project && nominatim index

# Check import log
tail -100 ~/nominatim-project/import.log
```

---

## Enclave / Air-Gapped Deployment

To deploy Nominatim in an environment with no internet access:

1. **Build the image** while internet is available:
   ```bash
   docker build -t nominatim:local .
   ```

2. **Download OSM data** before going offline (Step 5 above).

3. **Save the image** as a tarball for transfer:
   ```bash
   docker save nominatim:local | gzip > nominatim-image.tar.gz
   ```

4. **Transfer** the tarball and your `.osm.pbf` data file to the enclave.

5. **Load the image** on the enclave host:
   ```bash
   docker load < nominatim-image.tar.gz
   ```

6. **Start the container** — no internet required after this point:
   ```bash
   docker compose up
   ```

---

## Updating the Database with a New PBF File

When newer OSM data is available, the recommended approach for an air-gapped enclave
is a full re-import. The service will be unavailable during the import.

1. **Download the new PBF file** while internet is available (before going offline):
   ```bash
   wget -O data/massachusetts-latest.osm.pbf \
     https://download.geofabrik.de/north-america/us/massachusetts-latest.osm.pbf
   ```

2. **Update `OSM_FILE`** in `docker-compose.yml` if the filename changed.

3. **Stop the container and wipe the database volumes:**
   ```bash
   docker compose down
   docker volume rm nominatim_nominatim-pgdata nominatim_nominatim-project
   ```

4. **Start the container** — the import will run automatically:
   ```bash
   docker compose up
   ```

   Expected downtime:
   - Massachusetts: ~1.5 hours
   - US Northeast: ~2–4 hours
   - North America: ~24+ hours

> **Note:** Only the database volumes are removed. The `data/` folder with your PBF file
> is a bind mount on the host filesystem and is unaffected.

---

## Known Package Notes

| Package / Component | Note |
|---|---|
| `osmium-tool` | Not available in EPEL 9; not required for Nominatim 4.x |
| `osmium` | Correct PyPI package name (not `pyosmium`) |
| `curl` | AlmaLinux 9 ships `curl-minimal` which conflicts with full `curl`; use `wget` instead |
| Python | Must be 3.10+ for the `osmium` PyPI package; Dockerfile installs Python 3.11 |
| `initdb` | Must use `--locale=C.UTF-8 --encoding=UTF8`; plain `C` locale sets SQL_ASCII encoding which causes psycopg2 to return text as bytes, breaking the Nominatim import |
| `initdb` | Must run at container startup (in `entrypoint.sh`), not during Docker build; baking initdb into the image layer causes PostGIS compatibility issues |

---

## Troubleshooting

### `pg_ctl: cannot be run as root`
**Symptom:** Running `sudo pg_ctl ...` fails with this message.  
**Cause:** Plain `sudo` elevates to root, and PostgreSQL refuses to start as root.  
**Fix:** Always target the `postgres` user explicitly:
```bash
sudo -u postgres /usr/pgsql-17/bin/pg_ctl -D /var/lib/pgsql/17/data -l /var/log/postgresql/postgresql.log start
```

### `createuser: role "nominatim" does not exist`
**Symptom:** Running `createuser -s nominatim` as the `nominatim` Linux user fails.  
**Cause:** `createuser` tries to connect as the `nominatim` PostgreSQL role, which doesn't exist yet.  
**Fix:** Create both roles via `sudo -u postgres`:
```bash
sudo -u postgres createuser -s nominatim
sudo -u postgres createuser www-data
```

### `database files are incompatible with server`
**Symptom:** PostgreSQL fails to start with a message like:  
`The data directory was initialized by PostgreSQL version 15, which is not compatible with this version 17`  
**Cause:** The `nominatim-pgdata` Docker volume was previously initialized by a different
PostgreSQL version (e.g. from an earlier image build or a version change).  
**Fix:** Exit the container, remove the stale volume, and reinitialize. The OSM data
in the `nominatim-data` volume is unaffected.
```bash
# On the host (outside the container):
docker stop nominatim && docker rm nominatim
docker volume rm nominatim-pgdata

# Re-run the container (Docker creates a fresh empty volume automatically)
docker run -it --name nominatim --user nominatim \
  -p 8088:8088 -p 5432:5432 \
  -v nominatim-data:/data \
  -v nominatim-pgdata:/var/lib/pgsql/17/data \
  nominatim:local /bin/bash

# Inside the container — clear the mount point and reinitialize
sudo find /var/lib/pgsql/17/data/ -mindepth 1 -delete
sudo -u postgres /usr/pgsql-17/bin/initdb -D /var/lib/pgsql/17/data
```

### `initdb: directory exists but is not empty`
**Symptom:** `initdb` fails because the data directory already has files.  
**Cause:** The volume mount point cannot be `rm -rf`'d (device busy), so you must delete
the *contents* instead.  
**Fix:**
```bash
sudo find /var/lib/pgsql/17/data/ -mindepth 1 -delete
sudo -u postgres /usr/pgsql-17/bin/initdb -D /var/lib/pgsql/17/data
```

### `docker volume rm: volume is in use`
**Symptom:** `docker volume rm nominatim-pgdata` fails with "volume is in use".  
**Cause:** The container is still running or exists (even if stopped).  
**Fix:** Stop and remove the container first:
```bash
docker stop nominatim && docker rm nominatim
docker volume rm nominatim-pgdata
```

### `TypeError: a bytes-like object is required, not 'str'` during import
**Symptom:** The Nominatim import crashes immediately with this traceback in `postgis_version_tuple`.  
**Cause:** The PostgreSQL cluster was initialized with the plain `C` locale, which sets the
database encoding to `SQL_ASCII`. Psycopg2 returns text query results as bytes under SQL_ASCII,
causing the PostGIS version string to be bytes instead of a str.  
**Fix:** Always initialize the PostgreSQL cluster with UTF-8 encoding explicitly:
```bash
sudo -u postgres /usr/pgsql-17/bin/initdb --locale=C.UTF-8 --encoding=UTF8 -D /var/lib/pgsql/17/data
```
The Docker Compose path handles this automatically in `entrypoint.sh`. For manual setup,
make sure to include the `--locale` and `--encoding` flags when running `initdb`.

### `tee: Permission denied` on import log
**Symptom:** During the Docker Compose import, `tee` fails to write `import.log`.  
**Cause:** The `nominatim-project` Docker volume is created and owned by root, but the
container runs as the `nominatim` user.  
**Fix:** The `entrypoint.sh` uses `sudo mkdir` and `sudo chown` to set correct ownership
before running the import. If you hit this manually, run:
```bash
sudo chown nominatim:nominatim ~/nominatim-project
```

---

## References

- Nominatim Documentation: https://nominatim.org/release-docs/latest/
- Nominatim GitHub: https://github.com/osm-search/Nominatim
- Geofabrik Downloads: https://download.geofabrik.de/
- PostGIS Documentation: https://postgis.net/documentation/
