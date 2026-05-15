# Nominatim — Local Geocoding Server

A fully offline geocoding service built on [Nominatim](https://nominatim.org/) and OpenStreetMap data, packaged as a Docker container for deployment in air-gapped environments such as secure HPC enclaves.

## Stack

| Component | Version |
|---|---|
| Base OS | AlmaLinux 9 |
| PostgreSQL | 17 (PGDG) |
| PostGIS | 3.5 |
| Python | 3.11 |
| Nominatim | 4.5.0 |

---

## Prerequisites

- Docker with Docker Compose
- An OSM extract file (`.osm.pbf`) downloaded before going offline
  - Download from [Geofabrik](https://download.geofabrik.de/)

---

## Quick Start

### 1. Download OSM data

```bash
mkdir -p data
wget -O data/massachusetts-latest.osm.pbf \
  https://download.geofabrik.de/north-america/us/massachusetts-latest.osm.pbf
```

### 2. Build and start

```bash
docker compose up --build
```

On first run this will:
- Initialize the PostgreSQL database
- Import the OSM data (expect ~1.5 hours for Massachusetts)
- Start the Nominatim API on port 8088

On subsequent runs it detects the existing database and skips the import, starting the API in seconds.

### 3. Test the API

```bash
# Forward geocoding
curl "http://localhost:8088/search?q=Boston+City+Hall&format=json" | python3 -m json.tool

# Reverse geocoding
curl "http://localhost:8088/reverse?lat=42.3601&lon=-71.0942&format=json" | python3 -m json.tool
```

---

## Files

| File | Description |
|---|---|
| `Dockerfile` | Container image definition |
| `docker-compose.yml` | Compose configuration — ports, volumes, environment |
| `entrypoint.sh` | Container startup script — handles initdb, import, and API launch |
| `SETUP.md` | Full setup guide including manual setup, troubleshooting, and air-gapped deployment |
| `tests/` | Python and R test scripts with a sample Massachusetts address CSV |
| `data/` | Place your `.osm.pbf` file here before running (bind-mounted into the container) |

---

## API Endpoints

| Endpoint | Description | Example |
|---|---|---|
| `/search` | Forward geocoding | `/search?q=Fenway+Park&format=json` |
| `/reverse` | Reverse geocoding | `/reverse?lat=42.35&lon=-71.10&format=json` |
| `/lookup` | Lookup by OSM ID | `/lookup?osm_ids=R1804325&format=json` |
| `/status` | Server health check | `/status?format=json` |

Full API documentation: https://nominatim.org/release-docs/latest/api/Search/

---

## Air-Gapped Deployment

Build the image and save it as a tarball while internet is available:

```bash
docker compose build
docker save nominatim-nominatim | gzip > nominatim-image.tar.gz
```

Transfer `nominatim-image.tar.gz` and your `.osm.pbf` file to the enclave, then:

```bash
docker load < nominatim-image.tar.gz
# Place the .osm.pbf file in the data/ folder, then:
docker compose up
```

See `SETUP.md` for full details.

---

## Updating the Database

To import a newer OSM extract, stop the service, wipe the database volumes, and restart:

```bash
docker compose down
docker volume rm nominatim_nominatim-pgdata nominatim_nominatim-project
# Replace the .osm.pbf file in data/ if needed, then:
docker compose up
```

---

## Testing

Python and R test scripts are provided in the `tests/` folder.

**Python** (requires `pip install requests geopy pandas`):
```bash
python tests/test_nominatim.py
```

**R** (requires `httr`, `jsonlite`, `dplyr`, `readr`):
```bash
Rscript tests/test_nominatim.R
```

Both scripts test forward geocoding, reverse geocoding, structured address search, and batch geocoding from `tests/sample_addresses.csv`.
