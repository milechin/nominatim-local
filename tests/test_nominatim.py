#!/usr/bin/env python3
"""
Nominatim Local Server Test Script
===================================
Tests forward geocoding, reverse geocoding, and batch geocoding from a CSV file
against a locally running Nominatim instance.

Requirements:
    pip install requests geopy pandas

Usage:
    python test_nominatim.py

Make sure the Nominatim container is running first:
    docker compose up
"""

import time
import requests
import pandas as pd
from pathlib import Path
from geopy.geocoders import Nominatim
from geopy.exc import GeocoderTimedOut, GeocoderServiceError, GeocoderUnavailable

# =============================================================================
# Configuration
# =============================================================================

NOMINATIM_URL = "http://localhost:8088"
CSV_FILE = Path(__file__).parent / "sample_addresses.csv"
OUTPUT_FILE = Path(__file__).parent / "geocoded_results.csv"

# Delay between requests (seconds) — be kind to the server even when local
REQUEST_DELAY = 0.1


# =============================================================================
# Test 1 — Direct API call using requests
# =============================================================================

def test_forward_geocoding():
    """Forward geocoding: address string → coordinates."""
    print("\n" + "=" * 60)
    print("TEST 1: Forward Geocoding (direct API)")
    print("=" * 60)

    queries = [
        "Boston City Hall, Boston, MA",
        "Fenway Park, Boston, MA",
        "77 Massachusetts Ave, Cambridge, MA",
    ]

    for query in queries:
        response = requests.get(
            f"{NOMINATIM_URL}/search",
            params={"q": query, "format": "json", "limit": 1},
            timeout=10
        )
        response.raise_for_status()
        results = response.json()

        if results:
            r = results[0]
            print(f"\nQuery:   {query}")
            print(f"Name:    {r.get('display_name', 'N/A')[:80]}...")
            print(f"Lat/Lon: {r['lat']}, {r['lon']}")
            print(f"Type:    {r.get('type', 'N/A')}")
        else:
            print(f"\nQuery:   {query}")
            print("Result:  No results found")

        time.sleep(REQUEST_DELAY)


# =============================================================================
# Test 2 — Reverse geocoding using requests
# =============================================================================

def test_reverse_geocoding():
    """Reverse geocoding: coordinates → address."""
    print("\n" + "=" * 60)
    print("TEST 2: Reverse Geocoding (direct API)")
    print("=" * 60)

    coordinates = [
        (42.3505, -71.1054, "Boston University"),
        (42.3467, -71.0972, "Fenway Park area"),
        (42.3601, -71.0589, "Downtown Boston"),
    ]

    for lat, lon, label in coordinates:
        response = requests.get(
            f"{NOMINATIM_URL}/reverse",
            params={"lat": lat, "lon": lon, "format": "json"},
            timeout=10
        )
        response.raise_for_status()
        result = response.json()

        print(f"\nCoordinates: {lat}, {lon} ({label})")
        if "display_name" in result:
            print(f"Address:     {result['display_name'][:100]}")
            addr = result.get("address", {})
            print(f"Road:        {addr.get('road', 'N/A')}")
            print(f"City:        {addr.get('city', addr.get('town', 'N/A'))}")
            print(f"Postcode:    {addr.get('postcode', 'N/A')}")
        else:
            print("Result:      No address found")

        time.sleep(REQUEST_DELAY)


# =============================================================================
# Test 3 — Structured address search using requests
# =============================================================================

def test_structured_search():
    """Structured geocoding: individual address fields → coordinates."""
    print("\n" + "=" * 60)
    print("TEST 3: Structured Address Search (direct API)")
    print("=" * 60)

    addresses = [
        {"street": "360 Huntington Ave", "city": "Boston", "state": "MA", "country": "US"},
        {"street": "75 Francis Street",  "city": "Boston", "state": "MA", "country": "US"},
        {"street": "700 Boylston Street","city": "Boston", "state": "MA", "country": "US"},
    ]

    for addr in addresses:
        params = {**addr, "format": "json", "limit": 1}
        response = requests.get(f"{NOMINATIM_URL}/search", params=params, timeout=10)
        response.raise_for_status()
        results = response.json()

        query_str = f"{addr['street']}, {addr['city']}, {addr['state']}"
        if results:
            r = results[0]
            print(f"\nAddress: {query_str}")
            print(f"Match:   {r.get('display_name', 'N/A')[:80]}...")
            print(f"Lat/Lon: {r['lat']}, {r['lon']}")
        else:
            print(f"\nAddress: {query_str}")
            print("Result:  No results found")

        time.sleep(REQUEST_DELAY)


# =============================================================================
# Test 4 — Batch geocoding from CSV using geopy
# =============================================================================

def test_batch_geocoding_from_csv():
    """Read addresses from a CSV file, geocode each one, and write results."""
    print("\n" + "=" * 60)
    print("TEST 4: Batch Geocoding from CSV (using geopy)")
    print("=" * 60)
    print(f"Input:  {CSV_FILE}")
    print(f"Output: {OUTPUT_FILE}\n")

    # Configure geopy to use the local Nominatim server
    geolocator = Nominatim(
        user_agent="nominatim-test",
        domain="localhost:8088",
        scheme="http"
    )

    # Verify geopy is pointing at the correct server before batch run
    print(f"  geopy API URL: {geolocator.api}")
    try:
        probe = geolocator.geocode("Boston City Hall, Boston, MA", timeout=10)
        if probe:
            print(f"  geopy probe:   OK → {probe.latitude}, {probe.longitude}")
        else:
            print("  geopy probe:   returned None — check server connectivity")
            print("  Falling back to requests for batch geocoding.\n")
            _batch_with_requests(pd.read_csv(CSV_FILE))
            return
    except Exception as e:
        print(f"  geopy probe:   ERROR — {e}")
        print("  Falling back to requests for batch geocoding.\n")
        _batch_with_requests(pd.read_csv(CSV_FILE))
        return

    print()
    # Read zip as string to preserve leading zeros (e.g. 02215 not 2215)
    df = pd.read_csv(CSV_FILE, dtype={"zip": str})
    results = []

    for _, row in df.iterrows():
        full_address = f"{row['address']}, {row['city']}, {row['state']} {row['zip']}"

        try:
            location = geolocator.geocode(full_address, timeout=10)
            if location:
                lat = location.latitude
                lon = location.longitude
                display = location.raw.get("display_name", "")[:100]
                status = "OK"
            else:
                lat = lon = None
                display = ""
                status = "NOT FOUND"
        except GeocoderTimedOut:
            lat = lon = None
            display = ""
            status = "TIMEOUT"
        except (GeocoderServiceError, GeocoderUnavailable) as e:
            lat = lon = None
            display = ""
            status = f"ERROR: {e}"

        results.append({
            "id": row["id"],
            "name": row["name"],
            "input_address": full_address,
            "status": status,
            "latitude": lat,
            "longitude": lon,
            "matched_address": display,
        })

        icon = "✓" if status == "OK" else "✗"
        print(f"  [{icon}] {row['name'][:40]:<40} {status}")
        if lat:
            print(f"       → {lat:.6f}, {lon:.6f}")

        time.sleep(REQUEST_DELAY)

    _write_results(results)


def _batch_with_requests(df):
    """Fallback batch geocoder using requests directly."""
    results = []
    # Ensure zip is string to preserve leading zeros
    df = df.astype({"zip": str})
    for _, row in df.iterrows():
        full_address = f"{row['address']}, {row['city']}, {row['state']} {row['zip']}"
        try:
            response = requests.get(
                f"{NOMINATIM_URL}/search",
                params={"q": full_address, "format": "json", "limit": 1},
                timeout=10
            )
            response.raise_for_status()
            data = response.json()
            if data:
                r = data[0]
                lat, lon = float(r["lat"]), float(r["lon"])
                display = r.get("display_name", "")[:100]
                status = "OK"
            else:
                lat = lon = None
                display = ""
                status = "NOT FOUND"
        except requests.exceptions.RequestException as e:
            lat = lon = None
            display = ""
            status = f"ERROR: {e}"

        results.append({
            "id": row["id"],
            "name": row["name"],
            "input_address": full_address,
            "status": status,
            "latitude": lat,
            "longitude": lon,
            "matched_address": display,
        })

        icon = "✓" if status == "OK" else "✗"
        print(f"  [{icon}] {row['name'][:40]:<40} {status}")
        if lat:
            print(f"       → {lat:.6f}, {lon:.6f}")

        time.sleep(REQUEST_DELAY)

    _write_results(results)


def _write_results(results):
    """Write geocoding results to CSV and print summary."""
    results_df = pd.DataFrame(results)
    results_df.to_csv(OUTPUT_FILE, index=False)
    found = sum(1 for r in results if r["status"] == "OK")
    print(f"\nSummary: {found}/{len(results)} addresses geocoded successfully")
    print(f"Results saved to: {OUTPUT_FILE}")


# =============================================================================
# Test 5 — Server status check
# =============================================================================

def test_server_status():
    """Check that the Nominatim server is reachable and healthy."""
    print("\n" + "=" * 60)
    print("TEST 0: Server Status Check")
    print("=" * 60)

    try:
        response = requests.get(
            f"{NOMINATIM_URL}/status",
            params={"format": "json"},
            timeout=5
        )
        response.raise_for_status()
        status = response.json()
        print(f"Status:  {status.get('status', 'unknown')}")
        print(f"Message: {status.get('message', 'N/A')}")
        print(f"Data updated: {status.get('data_updated', 'N/A')}")
        return True
    except requests.exceptions.ConnectionError:
        print(f"ERROR: Cannot connect to Nominatim at {NOMINATIM_URL}")
        print("       Make sure the container is running: docker compose up")
        return False


# =============================================================================
# Main
# =============================================================================

if __name__ == "__main__":
    print(f"Nominatim Local Server Tests")
    print(f"Server: {NOMINATIM_URL}")

    if not test_server_status():
        exit(1)

    test_forward_geocoding()
    test_reverse_geocoding()
    test_structured_search()
    test_batch_geocoding_from_csv()

    print("\n" + "=" * 60)
    print("All tests complete.")
    print("=" * 60)
