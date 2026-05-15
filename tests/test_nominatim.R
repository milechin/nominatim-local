# =============================================================================
# Nominatim Local Server Test Script (R)
# =============================================================================
# Tests forward geocoding, reverse geocoding, and batch geocoding from a CSV
# against a locally running Nominatim instance.
#
# Required packages:
#   install.packages(c("httr", "jsonlite", "tidygeocoder", "dplyr", "readr"))
#
# Usage:
#   Rscript test_nominatim.R
#   Or run interactively section by section in RStudio.
#
# Make sure the Nominatim container is running first:
#   docker compose up
# =============================================================================

library(httr)
library(jsonlite)
library(dplyr)
library(readr)

NOMINATIM_URL <- "http://localhost:8088"
CSV_FILE      <- file.path(dirname(sys.frame(1)$ofile), "sample_addresses.csv")
OUTPUT_FILE   <- file.path(dirname(sys.frame(1)$ofile), "geocoded_results_r.csv")

# If running interactively, set paths manually:
# CSV_FILE    <- "sample_addresses.csv"
# OUTPUT_FILE <- "geocoded_results_r.csv"

cat(sprintf("Nominatim Local Server Tests (R)\nServer: %s\n", NOMINATIM_URL))


# =============================================================================
# Helper: low-level GET wrapper
# =============================================================================

nominatim_get <- function(endpoint, params) {
  url <- paste0(NOMINATIM_URL, endpoint)
  resp <- GET(url, query = params, timeout(10))
  stop_for_status(resp)
  fromJSON(content(resp, as = "text", encoding = "UTF-8"), flatten = TRUE)
}


# =============================================================================
# Test 0 — Server status check
# =============================================================================

cat("\n", strrep("=", 60), "\n", sep = "")
cat("TEST 0: Server Status Check\n")
cat(strrep("=", 60), "\n", sep = "")

tryCatch({
  status <- nominatim_get("/status", list(format = "json"))
  cat(sprintf("Status:       %s\n", status$status))
  cat(sprintf("Message:      %s\n", status$message))
  cat(sprintf("Data updated: %s\n", status$data_updated))
}, error = function(e) {
  cat(sprintf("ERROR: Cannot connect to Nominatim at %s\n", NOMINATIM_URL))
  cat("       Make sure the container is running: docker compose up\n")
  stop(e)
})


# =============================================================================
# Test 1 — Forward geocoding
# =============================================================================

cat("\n", strrep("=", 60), "\n", sep = "")
cat("TEST 1: Forward Geocoding (direct API)\n")
cat(strrep("=", 60), "\n", sep = "")

queries <- c(
  "Boston City Hall, Boston, MA",
  "Fenway Park, Boston, MA",
  "77 Massachusetts Ave, Cambridge, MA"
)

for (q in queries) {
  results <- nominatim_get("/search", list(q = q, format = "json", limit = 1))
  cat(sprintf("\nQuery:   %s\n", q))
  if (length(results) > 0 && is.data.frame(results)) {
    cat(sprintf("Name:    %s\n", substr(results$display_name[1], 1, 80)))
    cat(sprintf("Lat/Lon: %s, %s\n", results$lat[1], results$lon[1]))
    cat(sprintf("Type:    %s\n", results$type[1]))
  } else {
    cat("Result:  No results found\n")
  }
  Sys.sleep(0.1)
}


# =============================================================================
# Test 2 — Reverse geocoding
# =============================================================================

cat("\n", strrep("=", 60), "\n", sep = "")
cat("TEST 2: Reverse Geocoding (direct API)\n")
cat(strrep("=", 60), "\n", sep = "")

coords <- data.frame(
  lat   = c(42.3505, 42.3467, 42.3601),
  lon   = c(-71.1054, -71.0972, -71.0589),
  label = c("Boston University", "Fenway Park area", "Downtown Boston")
)

for (i in seq_len(nrow(coords))) {
  result <- nominatim_get("/reverse", list(
    lat    = coords$lat[i],
    lon    = coords$lon[i],
    format = "json"
  ))
  cat(sprintf("\nCoordinates: %.4f, %.4f (%s)\n",
              coords$lat[i], coords$lon[i], coords$label[i]))
  if (!is.null(result$display_name)) {
    cat(sprintf("Address:     %s\n", substr(result$display_name, 1, 100)))
    cat(sprintf("Road:        %s\n", result$address$road %||% "N/A"))
    cat(sprintf("City:        %s\n", result$address$city %||% result$address$town %||% "N/A"))
    cat(sprintf("Postcode:    %s\n", result$address$postcode %||% "N/A"))
  } else {
    cat("Result:      No address found\n")
  }
  Sys.sleep(0.1)
}

# NULL-coalescing helper used above
`%||%` <- function(a, b) if (!is.null(a)) a else b


# =============================================================================
# Test 3 — Structured address search
# =============================================================================

cat("\n", strrep("=", 60), "\n", sep = "")
cat("TEST 3: Structured Address Search (direct API)\n")
cat(strrep("=", 60), "\n", sep = "")

structured <- list(
  list(street = "360 Huntington Ave", city = "Boston",    state = "MA", country = "US"),
  list(street = "75 Francis Street",  city = "Boston",    state = "MA", country = "US"),
  list(street = "700 Boylston Street",city = "Boston",    state = "MA", country = "US")
)

for (addr in structured) {
  params <- c(addr, list(format = "json", limit = 1))
  results <- nominatim_get("/search", params)
  query_str <- sprintf("%s, %s, %s", addr$street, addr$city, addr$state)
  cat(sprintf("\nAddress: %s\n", query_str))
  if (length(results) > 0 && is.data.frame(results)) {
    cat(sprintf("Match:   %s\n", substr(results$display_name[1], 1, 80)))
    cat(sprintf("Lat/Lon: %s, %s\n", results$lat[1], results$lon[1]))
  } else {
    cat("Result:  No results found\n")
  }
  Sys.sleep(0.1)
}


# =============================================================================
# Test 4 — Batch geocoding from CSV using tidygeocoder
# =============================================================================

cat("\n", strrep("=", 60), "\n", sep = "")
cat("TEST 4: Batch Geocoding from CSV (using tidygeocoder)\n")
cat(strrep("=", 60), "\n", sep = "")
cat(sprintf("Input:  %s\n", CSV_FILE))
cat(sprintf("Output: %s\n\n", OUTPUT_FILE))

# tidygeocoder supports custom Nominatim endpoints via the 'custom_query'
# and 'api_url' arguments, or you can use the low-level geocode() with
# method = "osm" and a custom OSM_API setting.
#
# The simplest portable approach for a local server is a direct httr loop,
# which avoids any hardcoded Nominatim.org URLs in tidygeocoder internals.

addresses <- read_csv(CSV_FILE, show_col_types = FALSE)

geocode_address <- function(address, city, state, zip) {
  full_address <- sprintf("%s, %s, %s %s", address, city, state, zip)
  tryCatch({
    results <- nominatim_get("/search", list(
      q      = full_address,
      format = "json",
      limit  = 1
    ))
    if (length(results) > 0 && is.data.frame(results)) {
      list(
        status          = "OK",
        latitude        = as.numeric(results$lat[1]),
        longitude       = as.numeric(results$lon[1]),
        matched_address = substr(results$display_name[1], 1, 100)
      )
    } else {
      list(status = "NOT FOUND", latitude = NA, longitude = NA, matched_address = "")
    }
  }, error = function(e) {
    list(status = "ERROR", latitude = NA, longitude = NA, matched_address = "")
  })
}

results_list <- vector("list", nrow(addresses))

for (i in seq_len(nrow(addresses))) {
  row <- addresses[i, ]
  geo <- geocode_address(row$address, row$city, row$state, row$zip)

  results_list[[i]] <- data.frame(
    id              = row$id,
    name            = row$name,
    input_address   = sprintf("%s, %s, %s %s", row$address, row$city, row$state, row$zip),
    status          = geo$status,
    latitude        = geo$latitude,
    longitude       = geo$longitude,
    matched_address = geo$matched_address,
    stringsAsFactors = FALSE
  )

  icon <- if (geo$status == "OK") "✓" else "✗"
  cat(sprintf("  [%s] %-40s %s\n", icon, substr(row$name, 1, 40), geo$status))
  if (!is.na(geo$latitude)) {
    cat(sprintf("       → %.6f, %.6f\n", geo$latitude, geo$longitude))
  }

  Sys.sleep(0.1)
}

results_df <- bind_rows(results_list)
write_csv(results_df, OUTPUT_FILE)

found <- sum(results_df$status == "OK")
cat(sprintf("\nSummary: %d/%d addresses geocoded successfully\n", found, nrow(results_df)))
cat(sprintf("Results saved to: %s\n", OUTPUT_FILE))


# =============================================================================
# Summary
# =============================================================================

cat("\n", strrep("=", 60), "\n", sep = "")
cat("All tests complete.\n")
cat(strrep("=", 60), "\n", sep = "")
