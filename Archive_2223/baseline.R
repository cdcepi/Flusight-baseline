library(purrr)
library(dplyr)
library(readr)
library(tidyr)
library(lubridate)
library(ggplot2)
library(ggforce)

library(covidHubUtils)
library(simplets)

setwd(dirname(rstudioapi::getActiveDocumentContext()$path))
#devtools::install_github("reichlab/simplets")
source("fit_baseline_one_location.R")

# Set locations and quantiles
required_quantiles <-
  c(0.01, 0.025, seq(0.05, 0.95, by = 0.05), 0.975, 0.99)
required_locations <-
  readr::read_csv(file = "https://raw.githubusercontent.com/cdcepi/Flusight-forecast-data/master/data-locations/locations.csv") %>%
  dplyr::select("location", "abbreviation")

# The reference_date is the date of the Saturday relative to which week-ahead targets are defined.
# The forecast_date is the Monday of forecast creation.
# The forecast creation date is set to a Monday,
# even if we are delayed and create it Tuesday morning.
reference_date <- lubridate::floor_date(Sys.Date(), unit = "week") - 1
forecast_date <- as.character(reference_date + 2)

# Load data
data <- readr::read_csv("https://raw.githubusercontent.com/cdcepi/Flusight-forecast-data/master/data-truth/truth-Incident%20Hospitalizations.csv") %>%
  dplyr::filter(date >= "2021-12-04") %>%
  dplyr::arrange(location, date)

location_number <- nrow(required_locations)

# fit baseline models
quantile_forecasts <-
  purrr::map_dfr(
    required_locations$location,
    function(loc) {
      print(loc)
      location_data <- data %>%
        dplyr::filter(location == loc)
      location_results <-
        fit_baseline_one_location(
          reference_date = reference_date,
          location_data = location_data,
          transformation = "none",
          symmetrize = TRUE,
          window_size = nrow(data),
          taus = required_quantiles
        )
      return(location_results)
    }) %>%
  dplyr::select(-model)

if (!dir.exists("weekly-submission/forecasts/Flusight-baseline/")) {
  dir.create("weekly-submission/forecasts/Flusight-baseline/",
    recursive = TRUE)
}
if (!dir.exists("weekly-submission/plots/Flusight-baseline/")) {
  dir.create("weekly-submission/plots/Flusight-baseline/",
    recursive = TRUE)
}
base_file <- paste0("/Flusight-baseline/", forecast_date, "-Flusight-baseline")
results_path <- paste0("weekly-submission/forecasts", base_file, ".csv")
plot_path <- paste0("weekly-submission/plots", base_file, ".pdf")

# write forecast submission file
write.csv(quantile_forecasts, file = results_path, row.names = FALSE)

# plot
f <- covidHubUtils::load_forecasts_repo(
  file_path = paste0('weekly-submission/forecasts/'),
  models = 'Flusight-baseline',
  forecast_dates = forecast_date,
  locations = NULL,
  types = NULL,
  targets = NULL,
  hub = "FluSight",
  verbose = TRUE
)
p <-
  covidHubUtils::plot_forecasts(
    forecast_data = f,
    facet = "~location",
    hub = "FluSight",
    truth_source = "HealthData",
    subtitle = "none",
    title = "none",
    show_caption = FALSE,
    plot = FALSE
  ) +
  scale_x_date(
    breaks = "1 month",
    date_labels = "%b-%y",
    limits = as.Date(c(
      reference_date - (7 * 32), reference_date + 28
    ), format = "%b-%y")
  ) +
  theme(
    legend.position = "bottom",
    legend.direction = "vertical",
    legend.text = element_text(size = 8),
    legend.title = element_text(size = 8),
    axis.text.x = element_text(angle = 90),
    axis.title.x = element_blank()
  ) +
  ggforce::facet_wrap_paginate(
    ~ location,
    scales = "free",
    ncol = 2,
    nrow = 3,
    page = 1
  )
n <- n_pages(p)
pdf(
  plot_path,
  paper = 'A4',
  width = 205 / 25,
  height = 270 / 25
)
for (i in 1:n) {
  suppressWarnings(print(
    p + ggforce::facet_wrap_paginate(
      ~ location,
      scales = "free",
      ncol = 2,
      nrow = 3,
      page = i
    )
  ))
}
dev.off()
