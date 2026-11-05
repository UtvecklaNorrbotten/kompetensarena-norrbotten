# UKÄ HST source diagnostics: read-only, no publishing
Sys.setenv(UKA_LOAD_ONLY = "true")
source("R/etl/uka_sync.R")
Sys.unsetenv("UKA_LOAD_ONLY")
id <- 33L
university_html <- uka_filter_html(id, "university.php")
opts <- extract_options(university_html,"uni:")
message("University 171: ", paste(opts$name[opts$value == "uni:171"], collapse="; "))
groups <- extract_dynamic_groups(uka_filter_html(id,"group.php"))
totals <- unlist(lapply(groups,function(g) paste0(g$index, g$values[g$values == "dynamic:TOTAL"])),use.names=FALSE)
all_groups <- unlist(lapply(groups,function(g) paste0(g$index,g$values)),use.names=FALSE)
probe <- function(label,university,gender,ages,dynamic) {
 t <- Sys.time()
 res <- tryCatch({
   df <- uka_export(id,"from:2025/26","to:2025/26",university,gender,ages,dynamic)
   list(rows=nrow(df),university=unique(df$Lärosäte),
        genders=unique(df$Kön),ages=unique(df$Åldersgrupp))
 },error=function(e) list(error=conditionMessage(e)))
 message("PROBE_RESULT ",label,": ", jsonlite::toJSON(res,auto_unbox=TRUE),
         " elapsed=",round(as.numeric(difftime(Sys.time(),t,units="secs")),1))
}
probe("uni171_female_age8_total_groups","uni:171","gender:Kvinnor","age:8",totals)
probe("uni171_female_age_total_total_groups","uni:171","gender:Kvinnor","age:1",totals)
probe("uni171_total_gender_age_total_total_groups","uni:171","gender:Total","age:1",totals)
probe("uni171_female_age8_all_groups","uni:171","gender:Kvinnor","age:8",all_groups)
probe("riket_female_age8_total_groups","uni:1","gender:Kvinnor","age:8",totals)

message("DYNAMIC FILTER SPLIT PROBES")
study <- paste0(groups[[1]]$index,groups[[1]]$values)
subject <- paste0(groups[[2]]$index,groups[[2]]$values)
subject_parts <- split(subject,rep(1:2,length.out=length(subject)))
for (i in seq_along(subject_parts)) {
  probe(paste0("uni171_subject_half_",i),"uni:171","gender:Kvinnor","age:8",c(study,subject_parts[[i]]))
}
full <- uka_export(33L,"from:2025/26","to:2025/26","uni:1","gender:Total","age:1",c(study,subject))
parts <- lapply(subject_parts,function(x) uka_export(33L,"from:2025/26","to:2025/26","uni:1","gender:Total","age:1",c(study,x)))
combined <- dplyr::bind_rows(parts)
message("DYNAMIC_SPLIT_COUNTS ",jsonlite::toJSON(list(full=nrow(full),parts=vapply(parts,nrow,integer(1)),
 combined=nrow(combined),duplicates=nrow(combined)-nrow(dplyr::distinct(combined))),auto_unbox=TRUE))
