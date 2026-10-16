# Validation performed

- Inspected the supplied Python pipeline and all four existing output schemas.
- Inspected the Strava metadata headers and archive contents: 264 FIT files and
  one GPX file. Existing reference outputs have 264 summaries, 1,234 laps,
  817 whole-mile splits, and 67,062 sampled records.
- Checked FITfileR's current source (version 0.1.11) for its message accessors,
  automatic unit scaling, timestamp formatting, coordinate conversion, and
  multiple-message-definition return types.
- Executed `test_transformations.R` using WebR 0.6.0 (a WebAssembly R runtime).
  All checks passed: valid R syntax; elapsed-time mile interpolation;
  timer-time summary pace; fractional running cadence; cycling cadence exclusion;
  empty lap/record handling; endpoint-preserving record sampling; multisession
  rejection; and Windows/Unix filename normalization.

These deterministic tests supply decoded data at the parser boundary; they do
not test FITfileR's binary decoding. Native R was unavailable in the creation
environment. An end-to-end run against all 264 FIT files has not been completed,
so the reference counts above are comparison targets, not claimed new results.
The revised interpolation/cadence logic intentionally changes some values.

Run setup.R, then test_transformations.R, then your export. Review
fit_parse_log.csv before using the results. Use a new output folder for your
first comparison with the previous analysis pack.
