# Strava FIT -> analysis CSVs. R >= 4.1; see README.md.
# source() only defines functions. No installation or processing on source().

.fit_num <- function(x, name) {
  if (!name %in% names(x)) return(rep(NA_real_, nrow(x)))
  suppressWarnings(as.numeric(x[[name]]))
}
.fit_text <- function(x, name) {
  if (!name %in% names(x)) return(rep(NA_character_, nrow(x)))
  as.character(x[[name]])
}
.fit_time <- function(x, name) {
  if (!name %in% names(x)) return(rep(NA_character_, nrow(x)))
  v <- x[[name]]
  if (!inherits(v, 'POSIXt')) stop('Unexpected FIT timestamp type: ', name)
  format(v, '%Y-%m-%dT%H:%M:%SZ', tz = 'UTC')
}
.fit_messages <- function(fit, type) {
  x <- FITfileR::getMessagesByType(fit, as.integer(type))
  if (is.null(x)) return(data.frame())
  if (!is.data.frame(x)) x <- dplyr::bind_rows(x)
  as.data.frame(x)
}
.fit_key <- function(x) {
  x <- basename(gsub('\\\\', '/', x))
  sub('\\.(fit|gpx|tcx)(\\.gz)?$', '', x, ignore.case = TRUE)
}
.fit_pace <- function(distance, seconds) {
  ifelse(is.finite(distance) & distance > 0 & is.finite(seconds) & seconds > 0,
         seconds / 60 / (distance / 1609.344), NA_real_)
}
.fit_fraction <- function(x, name) {
  v <- .fit_num(x, name); v[is.na(v)] <- 0; v
}
.fit_cadence <- function(x, field, fractional, running) {
  v <- .fit_num(x, field) + .fit_fraction(x, fractional)
  if (running) 2 * v else rep(NA_real_, nrow(x))
}

.fit_tables <- function(fit, meta, sample_seconds = 10) {
  s <- .fit_messages(fit, 18)
  l <- .fit_messages(fit, 19)
  r <- .fit_messages(fit, 20)
  # A single session has unambiguous activity-level distance and sport.
  # Multisport needs session assignment before deriving cadence and mile splits.
  if (nrow(s) != 1L) stop('Expected one FIT session; found ', nrow(s),
                         '. Multisession files require separate handling.')
  sport <- tolower(.fit_text(s, 'sport')[1])
  running <- !is.na(sport) && sport %in% c('running', 'walking', 'hiking', '1', '11', '17')
  # Prefer FIT sport. Only fall back when the device omits sport.
  if (is.na(sport)) running <- meta$activity_type %in% c('Run', 'Trail Run', 'Virtual Run', 'Walk', 'Hike')
  meta$activity_date_utc <- .fit_time(s, 'start_time')[1]
  decorate <- function(x) {
    cbind(meta[rep(1L, nrow(x)), , drop = FALSE], x, row.names = NULL)
  }
  n <- function(name) .fit_num(s, name)
  summary <- data.frame(
    fit_start_time_utc = .fit_time(s, 'start_time'), sport = sport,
    distance_m = n('total_distance'), timer_time_s = n('total_timer_time'),
    elapsed_time_s = n('total_elapsed_time'),
    avg_pace_min_mi = .fit_pace(n('total_distance'), n('total_timer_time')),
    avg_hr = n('avg_heart_rate'), max_hr = n('max_heart_rate'),
    avg_cadence_cycles_min = n('avg_cadence'),
    avg_cadence_spm = .fit_cadence(s, 'avg_cadence', 'avg_fractional_cadence', running),
    max_cadence_cycles_min = n('max_cadence'),
    max_cadence_spm = .fit_cadence(s, 'max_cadence', 'max_fractional_cadence', running),
    avg_power_w = n('avg_power'), max_power_w = n('max_power'),
    normalized_power_w = n('normalized_power'), ascent_m = n('total_ascent'),
    descent_m = n('total_descent'), avg_temperature_c = n('avg_temperature'),
    aerobic_training_effect = n('total_training_effect'),
    avg_vertical_oscillation_mm = n('avg_vertical_oscillation'),
    avg_ground_contact_time_ms = n('avg_stance_time'),
    avg_vertical_ratio_pct = n('avg_vertical_ratio'), avg_step_length_mm = n('avg_step_length'))
  if ('start_time' %in% names(l)) l <- l[order(l$start_time, na.last = TRUE), , drop = FALSE]
  n <- function(name) .fit_num(l, name)
  laps <- data.frame(lap_index = seq_len(nrow(l)), start_time = .fit_time(l, 'start_time'),
    timestamp = .fit_time(l, 'timestamp'), total_distance_m = n('total_distance'),
    total_timer_time_s = n('total_timer_time'), total_elapsed_time_s = n('total_elapsed_time'),
    avg_pace_min_mi = .fit_pace(n('total_distance'), n('total_timer_time')),
    avg_heart_rate = n('avg_heart_rate'), max_heart_rate = n('max_heart_rate'),
    avg_cadence_spm = .fit_cadence(l, 'avg_cadence', 'avg_fractional_cadence', running),
    avg_power_w = n('avg_power'), max_power_w = n('max_power'),
    total_ascent_m = n('total_ascent'), total_descent_m = n('total_descent'),
    start_position_lat = n('start_position_lat'), start_position_long = n('start_position_long'),
    end_position_lat = n('end_position_lat'), end_position_long = n('end_position_long'))
  if (nrow(r)) {
    if (!'timestamp' %in% names(r)) stop('Records have no timestamp')
    r <- r[!is.na(r$timestamp), , drop = FALSE]
    r <- r[order(r$timestamp), , drop = FALSE]
    if (anyDuplicated(r$timestamp)) warning('Duplicate record timestamps retained; splits use first distance crossing')
  }
  n <- function(name) .fit_num(r, name)
  elapsed <- if (nrow(r)) as.numeric(difftime(r$timestamp, r$timestamp[1], units = 'secs')) else numeric()
  speed <- n('enhanced_speed'); speed[is.na(speed)] <- n('speed')[is.na(speed)]
  records <- data.frame(timestamp = .fit_time(r, 'timestamp'), elapsed_s = elapsed,
    distance_m = n('distance'), distance_mi = n('distance') / 1609.344,
    heart_rate = n('heart_rate'), cadence_spm = .fit_cadence(r, 'cadence', 'fractional_cadence', running),
    speed_mps = n('speed'), enhanced_speed_mps = n('enhanced_speed'),
    instant_pace_min_mi = ifelse(is.finite(speed) & speed > 0, 1609.344 / speed / 60, NA_real_),
    power_w = n('power'), altitude_m = n('altitude'), enhanced_altitude_m = n('enhanced_altitude'),
    temperature_c = n('temperature'), vertical_oscillation_mm = n('vertical_oscillation'),
    stance_time_ms = n('stance_time'), stance_time_percent = n('stance_time_percent'),
    position_lat = n('position_lat'), position_long = n('position_long'))
  # Derive crossings BEFORE downsampling. Linear interpolation of wall-clock time.
  # HR/cadence/power/elevation are nearest following record, NOT mile averages.
  splits <- data.frame(mile = integer(), split_time_s = numeric(), split_pace_min_mi = numeric(),
    elapsed_s_at_mile = numeric(), heart_rate_at_mile = numeric(), cadence_spm_at_mile = numeric(),
    power_at_mile = numeric(), elevation_m_at_mile = numeric())
  valid <- which(is.finite(records$distance_m) & is.finite(elapsed))
  if (length(valid) > 1L) {
    d <- records$distance_m[valid]; t <- elapsed[valid]
    if (any(diff(d) < -1)) {
      warning('Distance decreased by more than 1 m; derived mile splits omitted')
    } else if (d[1] > 20 || t[1] > 20) {
      warning('Record stream starts late; derived mile splits omitted')
    } else {
      # Remove tiny regressions and plateaus, retaining first arrival at each distance.
      keep <- !duplicated(cummax(d)); d <- cummax(d)[keep]; t <- t[keep]; ix <- valid[keep]
      miles <- seq_len(floor(max(d) / 1609.344))
      targets <- miles * 1609.344
      if (length(miles) && length(d) > 1L) {
        crossing <- stats::approx(d, t, xout = targets, rule = 1)$y
        at <- vapply(targets, function(target) ix[which(d >= target)[1]], integer(1))
        elev <- records$enhanced_altitude_m[at]
        elev[is.na(elev)] <- records$altitude_m[at][is.na(elev)]
        splits <- data.frame(mile = miles, split_time_s = diff(c(0, crossing)),
          split_pace_min_mi = diff(c(0, crossing)) / 60, elapsed_s_at_mile = crossing,
          heart_rate_at_mile = records$heart_rate[at], cadence_spm_at_mile = records$cadence_spm[at],
          power_at_mile = records$power_w[at], elevation_m_at_mile = elev)
      }
    }
  }
  # Keep first, last, and first record >= sample_seconds after previous kept record.
  keep <- integer(); last <- -Inf
  for (i in seq_len(nrow(records))) {
    if (i == 1L || i == nrow(records) || elapsed[i] - last >= sample_seconds) {
      keep <- c(keep, i); last <- elapsed[i]
    }
  }
  list(activity_summary = decorate(summary), laps_clean = decorate(laps),
       mile_splits_clean = decorate(splits), records_10s_clean = decorate(records[keep, , drop = FALSE]))
}

#' Rebuild the four CSV outputs from a ZIP, directory, or individual FIT/FIT.GZ.
#' metadata_csv may be NULL; unmatched activity IDs remain missing (never guessed).
#' strict=TRUE blocks publishing CSVs when any FIT file fails.
process_strava <- function(input, metadata_csv = NULL, output_dir = 'strava_csv',
                           sample_seconds = 10, strict = TRUE) {
  for (pkg in c('FITfileR', 'dplyr')) {
    if (!requireNamespace(pkg, quietly = TRUE)) stop('Install ', pkg, ' first; see README.md')
  }
  stopifnot(length(sample_seconds) == 1L, is.finite(sample_seconds), sample_seconds > 0)
  if (!file.exists(input)) stop('Input not found: ', input)
  scratch <- tempfile('strava_'); dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  if (dir.exists(input)) {
    files <- list.files(input, recursive = TRUE, full.names = TRUE)
  } else if (grepl('\\.zip$', input, ignore.case = TRUE)) {
    members <- utils::unzip(input, list = TRUE)$Name
    members <- members[!grepl('/$', members)]
    # Reject traversal or absolute paths before extraction, including Windows paths.
    norm <- gsub('\\\\', '/', members)
    if (any(grepl('(^/|^[A-Za-z]:|(^|/)\\.\\.(/|$))', norm))) stop('Unsafe path in ZIP')
    selected <- members[grepl('\\.(fit(\\.gz)?|gpx(\\.gz)?|tcx(\\.gz)?|csv)$', members, ignore.case = TRUE)]
    if (!length(selected)) stop("No supported activity files found in ZIP")
    utils::unzip(input, files = selected, exdir = scratch)
    files <- file.path(scratch, selected)
  } else files <- input
  if (is.null(metadata_csv)) {
    candidates <- files[tolower(basename(files)) == 'activities.csv']
    if (length(candidates) == 1L) metadata_csv <- candidates
  }
  meta <- data.frame()
  if (!is.null(metadata_csv)) {
    # Strava has duplicate headers; preserve originals and read IDs as character.
    meta <- utils::read.csv(metadata_csv, check.names = FALSE, colClasses = 'character',
                            fileEncoding = 'UTF-8-BOM', na.strings = '', stringsAsFactors = FALSE)
    required <- c('Activity ID', 'Filename', 'Activity Name', 'Activity Type', 'Activity Date')
    if (!all(required %in% names(meta))) stop('activities.csv lacks required Strava columns')
    meta$key <- .fit_key(meta$Filename)
    keys <- meta$key[!is.na(meta$key) & nzchar(meta$key)]
    if (anyDuplicated(keys)) stop('Ambiguous duplicate filenames in activities.csv')
  }
  fit_files <- sort(files[grepl('\\.fit(\\.gz)?$', files, ignore.case = TRUE)])
  if (!length(fit_files)) stop('No FIT or FIT.GZ files found. Extract nested ZIPs first.')
  if (anyDuplicated(.fit_key(fit_files))) stop('Duplicate FIT basenames; use one export at a time')
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(output_dir)) stop('Cannot create output directory')
  results <- vector('list', length(fit_files)); log <- vector('list', length(fit_files))
  for (i in seq_along(fit_files)) {
    path <- fit_files[i]; key <- .fit_key(path); notes <- character()
    index <- if (nrow(meta)) match(key, meta$key) else NA_integer_
    get <- function(name) if (is.na(index)) NA_character_ else meta[[name]][index]
    m <- data.frame(activity_id = get('Activity ID'), fit_file_id = key,
                    activity_date_utc = NA_character_, activity_name = get('Activity Name'),
                    activity_type = get('Activity Type'), activity_date_strava = get('Activity Date'))
    if (is.na(index)) notes <- 'No matching Strava metadata; activity_id left blank'
    status <- 'ok'; error <- ''
    result <- tryCatch(withCallingHandlers({
      source <- path
      if (grepl('\\.gz$', path, ignore.case = TRUE)) {
        source <- file.path(scratch, paste0('decoded_', i, '.fit'))
        # Connections are closed even if decompression fails.
        local({
          a <- gzfile(path, 'rb'); on.exit(close(a))
          b <- file(source, 'wb'); on.exit(close(b), add = TRUE)
          repeat {
            bytes <- readBin(a, 'raw', n = 1048576L)
            if (!length(bytes)) break
            writeBin(bytes, b)
          }
        })
      }
      parsed <- FITfileR::readFitFile(source)
      .fit_tables(parsed, m, sample_seconds)
    }, warning = function(w) {
      notes <<- c(notes, conditionMessage(w)); invokeRestart('muffleWarning')
    }), error = function(e) {
      status <<- 'error'; error <<- conditionMessage(e); NULL
    })
    results[i] <- list(result)
    log[[i]] <- data.frame(file = basename(path), fit_file_id = key, status = status,
                          metadata_matched = !is.na(index), warnings = paste(unique(notes), collapse = ' | '),
                          error = error)
    if (i %% 10L == 0L || i == length(fit_files)) message('Processed ', i, '/', length(fit_files))
  }
  report <- dplyr::bind_rows(log)
  utils::write.csv(report, file.path(output_dir, 'fit_parse_log.csv'), row.names = FALSE, na = '')
  skipped <- files[grepl('\\.(gpx|tcx)(\\.gz)?$', files, ignore.case = TRUE)]
  utils::write.csv(data.frame(file = basename(skipped), reason = rep('Non-FIT input not parsed', length(skipped))),
                   file.path(output_dir, 'fit_skipped_files.csv'), row.names = FALSE)
  if (strict && any(report$status == 'error')) stop('FIT failures: see fit_parse_log.csv. Existing analysis CSVs were not replaced.')
  results <- Filter(Negate(is.null), results)
  if (!length(results)) stop('No FIT files parsed successfully')
  output_names <- names(results[[1]])
  tables <- setNames(lapply(output_names, function(name) dplyr::bind_rows(lapply(results, `[[`, name))), output_names)
  for (name in output_names) {
    # Stage each output before replacing it. Use a fresh output directory for snapshots.
    dest <- file.path(output_dir, paste0('strava_fit_', name, '.csv'))
    temp <- tempfile('csv_', tmpdir = output_dir)
    utils::write.csv(tables[[name]], temp, row.names = FALSE, na = '', fileEncoding = 'UTF-8')
    if (!file.copy(temp, dest, overwrite = TRUE)) stop('Could not write ', dest)
    unlink(temp)
  }
  capture.output(sessionInfo(), file = file.path(output_dir, 'R_session_info.txt'))
  counts <- vapply(tables, nrow, integer(1))
  print(counts)
  if (any(report$status == 'error')) warning('Partial output: failed FIT files were omitted')
  invisible(list(counts = counts, log = report, output_dir = normalizePath(output_dir)))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (!length(args) || args[1] %in% c('-h', '--help')) {
    cat('Usage: Rscript strava_fit_pipeline.R INPUT OUTPUT_DIR [ACTIVITIES_CSV]\n')
  } else {
    if (length(args) < 2L || length(args) > 3L) stop('Expected INPUT OUTPUT_DIR [ACTIVITIES_CSV]')
    process_strava(args[1], if (length(args) == 3L) args[3] else NULL, args[2])
  }
}
