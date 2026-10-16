# Run once in R/RStudio (requires internet access).
cran <- 'https://cloud.r-project.org'
needed <- c('remotes', 'dplyr')
missing <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) install.packages(missing, repos = cran)
if (!requireNamespace('FITfileR', quietly = TRUE)) {
  remotes::install_github('grimbough/FITfileR', upgrade = 'never', build_vignettes = FALSE)
}
cat('Ready. FITfileR version:', as.character(packageVersion('FITfileR')), '\n')
