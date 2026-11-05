# Read-only integration test: the two UKÄ selections that triggered production failures.
Sys.setenv(UKA_LOAD_ONLY="true")
source("R/etl/uka_sync.R")
Sys.unsetenv("UKA_LOAD_ONLY")
id <- 33L
group_html <- uka_filter_html(id,"group.php")
groups <- extract_dynamic_groups(group_html)
dynamic_filters <- unlist(lapply(groups, function(g) paste0(g$index,g$values)),use.names=FALSE)
age_values <- extract_values(uka_filter_html(id,"age.php"),"age:")
uni_options <- extract_options(uka_filter_html(id,"university.php"),"uni:")
ltu <- uni_options$value[uni_options$name == "Luleå tekniska universitet"]
stopifnot(length(ltu)==1L)
test_universities <- c("uni:1","uni:171",ltu)
message("Read-only HST probe: ", length(dynamic_filters)," subject/study filters, ",length(age_values)," age groups")
raw <- uka_export_adaptive(id,"from:2025/26",test_universities,
                            "gender:Kvinnor",age_values,dynamic_filters)
stopifnot(nrow(raw)>0L, "Tidsperiod" %in% names(raw),
          all(clean_period(raw$Tidsperiod)=="2025/26"))
names_present <- unique(na.omit(as.character(raw$Lärosäte)))
stopifnot("Akademi för Ledarskap och Teologi" %in% names_present)
message("Read-only HST probe returned ",nrow(raw)," rows for ",
        length(names_present)," named universities (and optional Riket)")
normalized <- normalize_uka(raw,id,TRUE,TRUE)
observations <- build_observations(normalized)
stopifnot(!anyDuplicated(vapply(observations,function(o) jsonlite::toJSON(o,auto_unbox=TRUE),character(1))))
validate_uka_observations(observations,id,TRUE)
message("Read-only HST validation passed; no UKÄ database publishing")
