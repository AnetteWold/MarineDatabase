#' @title Export meta-data to NPI database input format
#' @description Exports meta-data from Excel files to the format accepted by NPI data managers
#' @param meta_file File name of the meta-data table. Currently only Excel files are supported.
#' @param sheet sheet number or name where meta-data are located. See \code{\link[openxlsx]{read.xlsx}}
#' @param expedition Column name specifying the name of the expedition.
#' @param station Column name specifying the station name.
#' @param type Column name specifying the sample type column.
#' @param sample_name Column name specifying the sample name column.
#' @param longitude Column name specifying the longitude column. Coordinates should be given in decimal degrees.
#' @param latitude Column name specifying the latitude column. Coordinates should be given in decimal degrees.
#' @param date Column name specifying the sampling time. The information will be transformed to ISO 8601 standard format.
#' @param bottom_depth Column name specifying the bottom depth during sampling.
#' @param gear Name of the column specifying the sampling gear.
#' @param from Name of the column specifying the depth from which sampling was started.
#' @param to Name of the column specifying the depth from which sampling was ended.
#' @param filtered_volume Name of the column specifying filtered volume in ml for filtered samples.
#' @param responsible Name of the column specifying the responsible persons for the sampling.
#' @param comment Name of the column specifying comments. Any non-numeric values in \code{from} and \code{to} will be transferred to this column.
#' @param additional Additional columns to be included in meta-data. Must be specified as a character vector, which lists exact column names to be included.
#' @details All column names should be specified as character strings of length 1. The column names refer to the meta-data table (\code{dt}).
#' @examples \donttest{
#' ## Read meta-data and let the function to find errors in it:
#' x <- export_metadata("Samplelog MOSJ 2015.xlsx")
#'
#' ## Meta-data reading follows openxlsx syntax:
#' x <- export_metadata("GlacierFront_2017_Samplelog_20171024.xlsx", sheet = "SAMPLELOG",
#' filtered_volume = "Filtration.volume.(ml)", responsible = "Contact.person")
#' }
#' @import openxlsx utils
#' @importFrom lubridate year month day
#' @export

#meta_file = paste0(devel, "Samplelog MOSJ 2015.xlsx") ;sheet = 1 ;expedition = "Expedition"; station = "Station"; type = "Sample.type"; sample_name = "Sample.name"; longitude = "Longitude.(decimals)"; latitude = "Latitude.(decimals)"; date = "Sampling.date.(UTC)"; bottom_depth = "Bottom.depth.(m)"; gear = "Gear"; from = "Sampling.depth.(m).from"; to = "Sampling.depth.(m).to"; filtered_volume = "Filtered.volume"; responsible = "Responsible.person"; comment = "Comment"; additional = NULL ; meta_file = paste0(twice, "GlacierFront_2017_Samplelog_20171024.xlsx"); sheet = "SAMPLELOG"; filtered_volume = "Filtration.volume.(ml)"; responsible = "Contact.person"

export_metadata <- function(meta_file, sheet = 1, expedition = "Expedition", station = "Station", type = "Sample.type", sample_name = "Sample.name", longitude = "Longitude.(decimals)", latitude = "Latitude.(decimals)", date = "Sampling.date.(UTC)", bottom_depth = "Bottom.depth.(m)", gear = "Gear", from = "Sampling.depth.(m).from", to = "Sampling.depth.(m).to", filtered_volume = "Filtered.volume", responsible = "Responsible.person", comment = "Comment", additional = NULL) {

file_ext <- getFileNameExtension(meta_file)

if(file_ext %in% c("xlsx", "xls")) {
  dt <- read.xlsx(meta_file, sheet = sheet)
} else {
  stop("Other read methods than Excel have not been implemented yet")
}

required_cols <- c("expedition", "station", "type", "sample_name", "longitude", "latitude", "date", "bottom_depth", "gear", "from", "to", "filtered_volume", "responsible", "comment")

sapply(required_cols, function(k) {
  if(!get(k) %in% colnames(dt)) {
    stop(paste(k, "was not found from column names of dt. Check column name specifications or add the column."))
  }
})

## Quality flag to whether meta-data can be merged with data

quality.flag <- TRUE
dups <- NULL
dup.rows <- NULL

## Structure

dt <- dt[c(unname(sapply(required_cols, function(k) get(k))), additional)]
colnames(dt) <- required_cols
dt <- rapply(object = dt, f = factor, classes = "character", how = "replace")

## Dates

if(is.numeric(dt$date) & file_ext %in% c("xlsx", "xls")) {
  dt$temp_date <- convertToDateTime(dt$date, tz = "UTC")
  dt$date <- strftime(as.POSIXct(dt$temp_date, "UTC"), "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
  message(paste("Date converted to ISO 8601 format. Stored as", class(dt$date), "class assuming", getDateOrigin(meta_file), "as origin date. Control that dates match with the Excel sheet."))
} else {
  stop("Implement new date conversion. Does not work for these data.")
}

## Expedition

levels(dt$expedition) <- gsub(" ", "", levels(dt$expedition))
dt <- droplevels(dt)

if(nlevels(dt) > 1) warning("There are several levels for expedition in the meta-data.")

## Station

if(any(duplicated(tolower(levels(dt$station))))) warning("Station names may contain typos. Check the station names from the output.")

## Sample type

data(sample_types)

dt$temp_type <- select(strsplit(as.character(dt$sample_name), "\\-"), 1)

i <- 2
tp <- lapply(1:nrow(dt), function(i) {
  tmp <- dt[i,]
  temp_type2 <- ifelse(length(TYPES[TYPES$code %in% tmp$temp_type ,"sample_type"]) == 0, NA, TYPES[TYPES$code %in% tmp$temp_type ,"sample_type"])
  tmp$temp_type2 <- temp_type2
  tmp
})

tp <- do.call(rbind, tp)

removed <- tp[is.na(tp$temp_type2),]

dt <- tp[!is.na(tp$temp_type2),]
dt$type <- factor(dt$temp_type2)

## Duplicated sample types

if(any(duplicated(dt[c("expedition", "sample_name")]))) {

  dups <- as.character(dt$sample_name[duplicated(dt[c("expedition", "sample_name")])])
  dup_dat <- tp[tp$sample_name %in% dups, c("sample_name", "type", "station")]
  dup_dat$row_number <- as.numeric(rownames(dup_dat)) +1
  dup_dat <-  dup_dat[order(dup_dat$sample_name),]
  rownames(dup_dat) <- 1:nrow(dup_dat)

  warning(paste(length(dups), "sample names are duplicated. Write $duplicates to see them. Note that this problem has to be fixed before you can use the meta-data to export data files"))
quality.flag <- FALSE
} else {
  dups <- NULL
  dup_dat <- NULL
}

## Coordinates

if(!is.numeric(dt$longitude)) {
  dt$longitude <- numeric(dt$longitude)
  warning("longitude converted to numeric. Check longitude records for possible mistakes. Should be decimal degrees")
}

if(!is.numeric(dt$latitude)) {
  dt$latitude <- numeric(dt$latitude)
  warning("latitude converted to numeric. Check latitude records for possible mistakes. Should be decimal degrees")
}

## Gear

data("gear_types")

i <- 1
tp <- lapply(1:nrow(dt), function(i) {
  #print(i)
  tmp <- dt[i,]
  if(!as.character(tmp$gear) %in% GEAR$gear) {
    tmp$gear <- as.character(tmp$gear)

    temp_gear <- agrep(tmp$gear, GEAR$gear, value = TRUE)

    # Exceptions
    if(tmp$gear == "Multinet") temp_gear <- grep("200", temp_gear, value = TRUE)
    if(tmp$gear == "CTD") temp_gear <- grep("Ship", temp_gear, value = TRUE)

    if(length(temp_gear) == 0) temp_gear <- agrep(gsub("[[:punct:]]", " ", tmp$gear), GEAR$gear, value = TRUE)

    if(length(temp_gear) != 1) stop(paste("Fuzzy matching", tmp$gear, "does not work for row", i))

    tmp$gear <- temp_gear
  } else {
    tmp$gear <- tmp$gear
  }
  tmp
})

dt <- do.call(rbind, tp)

dt$gear <- factor(dt$gear)

## Comments

dt$comment <- as.character(dt$comment)

## Sampling depths

if(!is.numeric(dt$from)) {
dt <- convert_sampling_depths(dt, "from")
}

if(!is.numeric(dt$to)) {
dt <- convert_sampling_depths(dt, "to")
}

## Filtered volume

if(!is.numeric(dt$filtered_volume)) {
  suppressWarnings(dt$filtered_volume <- as.numeric(dt$filtered_volume))
  warning("filtered_volume converted to numeric. NAs produced. Check the data.")
}

if(any(na.omit(dt$filtered_volume < 10))) warning("Filtered volumes should be given in ml. Values less than 10 ml were found. Are you sure?")
## Responsible

dt$responsible <- as.character(dt$responsible)

## Output parameters

file_id <- paste(levels(dt$expedition), "metadata", sep = "_")

## Remove temporary columns

dt <- dt[-grep("temp", colnames(dt))]

## Output

out <- list(dt, removed, file_id, dups, dup_dat, quality.flag)
names(out) <- c("meta", "deleted", "file_id", "duplicate_names", "duplicates", "merge_allowed")

class(out) <- "MetaData"

## Messages

if(nrow(out$deleted) != 0) message(paste(nrow(out$deleted), "entries removed. Write $deleted to see the entries"))

## Return

out

}


getFileNameExtension <- function (fn) {
# remove a path
splitted    <- strsplit(x=fn, split='/')[[1]]
# or use .Platform$file.sep in stead of '/'
fn          <- splitted [length(splitted)]
ext         <- ''
splitted    <- strsplit(x=fn, split='\\.')[[1]]
l           <-length (splitted)
if (l > 1 && sum(splitted[1:(l-1)] != ''))  ext <-splitted [l]
# the extention must be the suffix of a non-empty name
ext
}
