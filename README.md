# R pipeline for Strava FIT exports

Requires R 4.1 or later.

Converts Strava FIT activities into the four analysis CSVs used in your existing
analysis pack. Uses native R with FITfileR for FIT decoding; no Python needed.

## First run in RStudio

1. Extract this ZIP and open an RStudio project in the extracted folder.
2. Run `source("setup.R")` once to install dependencies (internet required).
3. Open `run_example.R`, edit the three paths, and run it.
   Use forward slashes in Windows paths, as shown in the example.

```r
source("strava_fit_pipeline.R")
process_strava(
  input = "C:/data/strava/activities.zip",
  metadata_csv = "C:/data/strava/activities.csv",
  output_dir = "C:/data/strava/output"
)
```

With an extracted full export, metadata is discovered automatically:

```r
process_strava("C:/data/strava/export", output_dir = "C:/data/strava/output")
```

Or from a terminal:

```sh
Rscript strava_fit_pipeline.R "C:/data/strava/activities.zip" "C:/data/strava/output" "C:/data/strava/activities.csv"
```

Rscript must be on your PATH for the terminal form. RStudio does not require this.

## Each new dump

Download/extract the new export, point `input` and `metadata_csv` at it, and rerun.
The pipeline rebuilds outputs from that input; it does not append to previous
outputs. This avoids double counting overlapping exports. A partial export will
produce partial history. To preserve snapshots, use a dated output directory.
The script never modifies your raw input files. Avoid running two jobs against
the same output directory at once.

The pipeline handles `.fit`, `.fit.gz`, directories recursively, and ZIP archives.
It reads one FIT file at a time and retains only the summary tables and sampled
record stream. No caching is used, so changes in metadata or logic are picked up
on the next run without clearing a cache.

## Outputs

| File | Contents |
| --- | --- |
| `strava_fit_activity_summary.csv` | One row per successfully parsed single-session FIT file |
| `strava_fit_laps_clean.csv` | Device-recorded laps, including timer-based pace |
| `strava_fit_mile_splits_clean.csv` | Whole-mile distance crossings derived from full-resolution records |
| `strava_fit_records_10s_clean.csv` | Approximately 10-second samples plus first and last record |
| `fit_parse_log.csv` | One row per input FIT, success/error status, metadata match, warnings |
| `fit_skipped_files.csv` | GPX/TCX files deliberately skipped |
| `R_session_info.txt` | R and dependency versions for reproducibility |

IDs are strings; `fit_file_id` is a filename stem, not a Strava activity ID.
The join uses `activities.csv`'s `Filename` column. Unmatched IDs remain blank
and are flagged. Duplicate filename keys stop processing rather than guessing.
When reading outputs back into R, preserve ID strings:

```r
activities <- read.csv("C:/data/strava/output/strava_fit_activity_summary.csv",
                       colClasses = c(activity_id = "character", fit_file_id = "character"))
```

Missing values are empty CSV cells. Distances are meters, times seconds, speed
m/s, pace decimal minutes/mile, coordinates degrees, temperatures Celsius, power
watts. Running dynamics retain FIT profile units (mm, ms, percent).
`activity_date_utc` and FIT timestamps are ISO UTC; `activity_date_strava` preserves
the original Strava date text. Convert UTC to your chosen timezone before grouping
by local day/week; this does not infer travel timezone from GPS.

## Interpretation and differences from the old Python pack

- FITfileR applies FIT scaling and coordinate conversion. This script does not
  apply scaling twice. Undecoded or absent fields remain missing.
- Running/walking/hiking cadence is doubled from cycles/minute to steps/minute,
  including fractional cadence when supplied. `*_spm` is blank for other sports;
  original session cadence remains in `*_cadence_cycles_min`. Check this assumption
  when using a new recording device or unusual sensor.
- Mile crossings use linear interpolation between full-resolution distance
  records, so they can differ slightly from your old next-record crossings.
  They measure **wall-clock elapsed time from the first timestamped record**;
  pauses are included. They are not moving-time splits. The final incomplete mile
  is omitted. HR/cadence/power/elevation at a crossing are readings from the next
  distance-crossing record, not averages over that mile.
- A distance regression over 1 meter or a stream starting over 20 m/seconds late
  suppresses derived splits and produces a warning. Small initial recording delay
  can still affect the first split. Large recording gaps make interpolation less
  reliable. Use watch laps for paused workouts.
- The record table selects observations; it is not a 10-second average or a
  perfectly regular time grid. It does not fill gaps. The default is 10 seconds.
  `sample_seconds` can be changed, but the familiar `records_10s_clean` filename
  remains unchanged; keep the default unless you deliberately want a different rate.
- Multisession/multisport files are rejected with a clear log entry; combining
  their distances/sports silently would create misleading summaries.
- GPX/TCX/manual activities do not appear in the FIT summaries. Keep the original
  activities.csv when you need a complete activity inventory.
- This exports selected standard FIT fields, not every proprietary developer field.
  Missing running dynamics or power should not be interpreted as zero.

## Errors and safe reruns

Default `strict = TRUE`: any FIT parsing failure writes the diagnostic logs and
stops **before replacing the four analysis CSVs**. Existing outputs then remain
from the previous run; do not confuse them with a successful refresh. Check the
log after every run, including warnings and unmatched metadata.

If you deliberately want results for the valid subset:

```r
process_strava("C:/data/strava/export", output_dir = "C:/data/strava/partial",
               strict = FALSE)
```

Each CSV is staged before copying into place, but publishing the four files is
not a transactional filesystem operation. A fresh dated output directory is best
if preserving a previous snapshot is important.

## Validation and dependencies

The code was written against the FITfileR 0.1.11 source and its documented
`readFitFile()` / `getMessagesByType()` interface, and the structure of your
supplied export and previous output pack. FITfileR supports either a tibble or
a list of tibbles per message type; both are handled here.

Source: https://github.com/grimbough/FITfileR
Documentation: https://msmith.de/FITfileR/articles/FITfileR.html

See VALIDATION.md for the checks actually completed in the creation environment.
For a new device, first compare a known run's distance, timer time, HR, cadence,
and lap count against its watch/Strava summary before relying on aggregate analysis.
