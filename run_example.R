# Open an RStudio project in this folder, then edit these three paths.
source('strava_fit_pipeline.R')

process_strava(
  input = 'C:/Users/David/Downloads/strava-export/activities.zip',
  metadata_csv = 'C:/Users/David/Downloads/strava-export/activities.csv',
  output_dir = 'C:/Users/David/Documents/Running/strava_csv'
)

# Alternatively: input can be the extracted export folder, a full export ZIP
# containing activities.csv and activities/, or a single .fit / .fit.gz file.
# For full exports, activities.csv is auto-detected (metadata_csv can be omitted).
# Extract nested ZIPs first; archives inside archives are not expanded.
