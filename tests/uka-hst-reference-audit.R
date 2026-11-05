# Read-only source audit for UKÄ HST. No ETL endpoint or database write.
Sys.setenv(UKA_LOAD_ONLY="true")
source("R/etl/uka_sync.R")
Sys.unsetenv("UKA_LOAD_ONLY")

id <- 33L
period <- "2025/26"
groups <- extract_dynamic_groups(uka_filter_html(id,"group.php"))
stopifnot(length(groups) == 2L)
study <- paste0(groups[[1]]$index,groups[[1]]$values)
subject <- paste0(groups[[2]]$index,groups[[2]]$values)
ages <- extract_values(uka_filter_html(id,"age.php"),"age:")
uni <- c("uni:1", "uni:171")
gender <- "gender:Kvinnor"
parts <- split(subject,rep(seq_len(2L),length.out=length(subject)))
message("AUDIT_META ",jsonlite::toJSON(list(ages=ages,study=length(study),
  subject=length(subject),subgroups=vapply(parts,length,integer(1))),auto_unbox=TRUE))
# Inspect hierarchy from actual filter tokens. Values such as 922_921 link child to parent.
tokens <- sub("^.*dynamic:","",subject)
tokens <- tokens[tokens!="TOTAL"]
depth <- vapply(strsplit(tokens,"_",fixed=TRUE),length,integer(1))
message("AUDIT_HIERARCHY levels=",paste(sort(table(depth)),collapse=","), 
  " examples=",paste(head(tokens,14),collapse="|"))

safe_export <- function(label,loc,age_vals,filters) {
  begin <- Sys.time()
  out <- tryCatch({
    dat <- uka_export(id,paste0("from:",period),paste0("to:",period),
                      loc,gender,age_vals,filters)
    list(ok=TRUE,rows=nrow(dat),data=dat)
  },error=function(e) list(ok=FALSE,error=conditionMessage(e)))
  message("AUDIT_EXPORT ",label," ",jsonlite::toJSON(
    if(out$ok) list(ok=TRUE,rows=out$rows,age_counts=as.list(table(as.character(out$data$Åldersgrupp))))
    else list(ok=FALSE,error=out$error),auto_unbox=TRUE),
    " seconds=",round(as.numeric(difftime(Sys.time(),begin,units="secs")),1))
  out
}
# Compare source observations, not just row counts.
keyed <- function(df) {
  names(df) <- gsub("\\[[012]\\]$","",names(df))
  df <- df[,sort(names(df)),drop=FALSE]
  df[] <- lapply(df,as.character)
  if ("Värde" %in% names(df)) df$Värde <- trimws(df$Värde)
  keys <- apply(df,1,function(row) jsonlite::toJSON(as.list(row),auto_unbox=TRUE,na="null"))
  sort(keys)
}
compare <- function(label,a,b) {
  if(!a$ok || !b$ok) return(invisible(NULL))
  ka <- keyed(a$data);kb <- keyed(b$data)
  message("AUDIT_COMPARE ",label," ",jsonlite::toJSON(list(
    exact=identical(ka,kb),count_a=length(ka),count_b=length(kb),
    duplicates_a=sum(duplicated(ka)),duplicates_b=sum(duplicated(kb)),
    only_a=length(setdiff(ka,kb)),only_b=length(setdiff(kb,ka))),auto_unbox=TRUE))
}

for (loc in uni) {
  label <- gsub(":", "_", loc)
  whole <- safe_export(paste0(label,"_allages_fullsubject"),loc,ages,c(study,subject))
  half <- lapply(seq_along(parts),function(i) safe_export(
    paste0(label,"_allages_half",i),loc,ages,c(study,parts[[i]])))
  if (all(vapply(half,function(x)x$ok,logical(1)))) {
    joined <- list(ok=TRUE,data=dplyr::bind_rows(lapply(half,function(x)x$data)))
    compare(paste0(label,"_allages_full_vs_halves"),whole,joined)
  }
  for (i in seq_along(parts)) {
    solo <- safe_export(paste0(label,"_age8_half",i),loc,"age:8",c(study,parts[[i]]))
    if (half[[i]]$ok) {
      filtered <- list(ok=TRUE,data=half[[i]]$data[as.character(half[[i]]$data$Åldersgrupp)=="-24",,drop=FALSE])
      compare(paste0(label,"_half",i,"_age8_vs_filtered_allages"),solo,filtered)
    }
  }
  source_total <- safe_export(paste0(label,"_source_total"),loc,"age:8",
                              c(study[1],subject[1]))
}

# Probe an intentionally tiny, hierarchy-sensitive selection. Do not infer
# that empty CSV means zero; distinguish an empty HTTP body from CSV headers.
raw_probe <- function(label,subject_values) {
 filters <- c("from:2025/26","to:2025/26","uni:171","gender:Kvinnor","age:8",study,subject_values)
 result <- tryCatch({
   response <- httr2::request(paste0(uka_base,"/api/index.php")) |>
     httr2::req_headers("Accept"="application/json","X-Requested-With"="XMLHttpRequest") |>
     httr2::req_body_form(indicator="33",`filters[]`=filters,.multi="explode") |>
     httr2::req_timeout(90) |> httr2::req_perform() |>
     httr2::resp_body_json(simplifyVector=TRUE)
   url <- response$fileUrl
   if (is.null(url) || !nzchar(url)) stop("Missing fileUrl")
   res <- uka_request(url) |> httr2::req_timeout(90) |> httr2::req_perform()
   raw <- httr2::resp_body_raw(res)
   body <- if(length(raw)) rawToChar(head(raw,300L)) else ""
   list(file_url_present=TRUE,status=httr2::resp_status(res),
        bytes=length(raw),preview=substr(body,1,180))
 },error=function(e)list(error=conditionMessage(e)))
 message("AUDIT_RAW ",label," ",jsonlite::toJSON(result,auto_unbox=TRUE))
}
# Prefix paths resemble the recursive splitter; also test a known valid total.
for (n in c(116L,58L,29L,14L,7L,3L,1L)) {
 selected <- parts[[1]][seq_len(n)]
 raw_probe(paste0("prefix_half1_",n),selected)
}
raw_probe("source_subject_total",subject[1])
# Probe branches not containing the "TOTAL" node: these can legitimately
# have no observations for a particular university/age/gender.
raw_probe("non_total_subject_2",subject[2])
raw_probe("non_total_subject_3",subject[3])
raw_probe("non_total_subject_4",subject[4])
raw_probe("non_total_half2_full",parts[[2]])
raw_probe("non_total_half2_first1",parts[[2]][1])
raw_probe("non_total_half2_first3",parts[[2]][1:3])
raw_probe("non_total_half2_last1",tail(parts[[2]],1))

message("AUDIT_RAW_DONE")

message("AUDIT_DONE read-only, no publishing")
