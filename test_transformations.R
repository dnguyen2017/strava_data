# Focused deterministic checks, without installing FITfileR.
# Run from this folder: Rscript test_transformations.R
source('strava_fit_pipeline.R')
# Replace only the FIT decoder boundary with already-decoded synthetic messages.
.fit_messages <- function(fit, type) fit[[as.character(type)]]
t0 <- as.POSIXct('2026-01-01 12:00:00', tz = 'UTC')
m <- data.frame(activity_id = '123456789012345', fit_file_id = '42',
                activity_date_utc = NA_character_, activity_name = 'Test',
                activity_type = 'Run', activity_date_strava = 'Original date')
s <- data.frame(start_time = t0, sport = 'running', total_distance = 3218.688,
                total_timer_time = 1200, total_elapsed_time = 1300,
                avg_cadence = 80, avg_fractional_cadence = 0.5)
r <- data.frame(timestamp = t0 + c(0, 300, 600, 900, 1300),
                distance = c(0, 800, 1600, 2400, 3218.688), heart_rate = 140,
                cadence = 80, fractional_cadence = 0.5, enhanced_speed = 3)
f <- list('18' = s, '19' = data.frame(), '20' = r)
x <- .fit_tables(f, m)
stopifnot(nrow(x$activity_summary) == 1L,
          x$activity_summary$avg_cadence_spm == 161,
          x$activity_summary$avg_pace_min_mi == 10,
          nrow(x$laps_clean) == 0L,
          nrow(x$mile_splits_clean) == 2L,
          abs(x$mile_splits_clean$elapsed_s_at_mile[1] - 603.504) < 1e-8,
          sum(x$mile_splits_clean$split_time_s) == 1300,
          x$records_10s_clean$timestamp[1] == '2026-01-01T12:00:00Z')
f[['18']]$sport <- 'cycling'
y <- .fit_tables(f, m)
stopifnot(is.na(y$activity_summary$avg_cadence_spm),
          all(is.na(y$records_10s_clean$cadence_spm)))
f[['20']] <- data.frame()
y <- .fit_tables(f, m)
stopifnot(nrow(y$records_10s_clean) == 0L, nrow(y$mile_splits_clean) == 0L)
f[['20']] <- data.frame(timestamp = t0 + 0:25, distance = 0:25)
y <- .fit_tables(f, m)
stopifnot(identical(y$records_10s_clean$elapsed_s, c(0, 10, 20, 25)))
f[['18']] <- rbind(s, s)
stopifnot(inherits(try(.fit_tables(f, m), silent = TRUE), 'try-error'))
stopifnot(.fit_key('activities/123.fit.gz') == '123',
          .fit_key('C:\\activities\\123.FIT') == '123')
cat('All transformation checks passed.\n')
