# Klient för SCB:s Allmänna företagsregister (AFR), API v1.
# API-nyckeln läses endast från miljövariabeln SCB_AFR_API_KEY och skickas
# i headern X-API-Key. Den skrivs aldrig ut, loggas aldrig och sparas aldrig.

suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
})

AFR_PAGE_LIMIT <- 5000L
AFR_API_VERSION <- "v1"

afr_stats <- new.env()
afr_stats$requests <- 0L
afr_stats$retries <- 0L
afr_stats$http_429 <- 0L
afr_stats$bytes <- 0

afr_base_url <- function() {
  sub("/+$", "", Sys.getenv("SCB_AFR_BASE_URL", unset = "https://apiafr.scb.se"))
}

afr_key <- function() {
  x <- Sys.getenv("SCB_AFR_API_KEY", unset = "")
  if (!nzchar(x)) stop("SCB_AFR_API_KEY saknas", call. = FALSE)
  x
}

# GET med retry/backoff på 429 och 5xx samt nätverksfel. Respekterar Retry-After.
afr_get <- function(path, query = list(), max_tries = 8L) {
  url <- paste0(afr_base_url(), "/", AFR_API_VERSION, path)
  for (attempt in seq_len(max_tries)) {
    req <- request(url) |>
      req_headers("X-API-Key" = afr_key(), "Accept" = "application/json") |>
      req_url_query(!!!query) |>
      req_timeout(180) |>
      req_error(is_error = function(resp) FALSE)

    afr_stats$requests <- afr_stats$requests + 1L
    resp <- tryCatch(req_perform(req), error = function(e) e)

    if (inherits(resp, "error")) {
      wait <- min(300, 2^attempt)
      message(sprintf("AFR nätverksfel (%s), försök %d – väntar %ds", conditionMessage(resp), attempt, wait))
      afr_stats$retries <- afr_stats$retries + 1L
      Sys.sleep(wait)
      next
    }

    status <- resp_status(resp)
    if (status >= 200 && status < 300) {
      raw <- resp_body_raw(resp)
      afr_stats$bytes <- afr_stats$bytes + length(raw)
      return(fromJSON(rawToChar(raw), simplifyVector = FALSE))
    }

    if (status == 429L || status >= 500L) {
      if (status == 429L) afr_stats$http_429 <- afr_stats$http_429 + 1L
      afr_stats$retries <- afr_stats$retries + 1L
      ra <- suppressWarnings(as.numeric(resp_header(resp, "Retry-After") %||% NA))
      wait <- if (!is.na(ra) && ra >= 0) min(600, ra + 1) else min(300, 2^attempt)
      message(sprintf("AFR HTTP %d på %s, försök %d – väntar %ds", status, path, attempt, wait))
      Sys.sleep(wait)
      next
    }

    stop(sprintf("AFR-anrop misslyckades (HTTP %d) för %s", status, path), call. = FALSE)
  }
  stop(sprintf("AFR-anrop gav upp efter %d försök: %s", max_tries, path), call. = FALSE)
}

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || (length(x) == 1 && is.na(x))) y else x
}

afr_api_info <- function() afr_get("/api-info")

afr_count <- function(entity) {
  path <- if (entity == "je") "/juridiskaenheter/count" else "/arbetsstallen/count"
  as.integer(afr_get(path)$count)
}

AFR_CODE_TABLES <- c(
  "naringsgrenkoder", "kommunkoder", "lankoder", "ftgstatkoder", "anstklkoder", "arbgivstatkoder",
  "aetypkoder", "jurformkoder", "omsklkoder", "agarkontrollkoder", "momsstatkoder", "fskattstatkoder",
  "bolstatkoder", "privpublkoder", "sektorkoder", "aestatkoder", "hjverksjekoder"
)

afr_fetch_code_tables <- function() {
  lapply(AFR_CODE_TABLES, function(name) {
    rows <- afr_get(paste0("/kodtabeller/", name))
    list(
      table = name,
      rows = lapply(rows, function(r) {
        extra <- r[setdiff(names(r), c("kod", "klartext"))]
        extra <- lapply(extra, function(v) if (is.null(v)) NULL else as.character(v))
        out <- list(kod = as.character(r$kod), klartext = if (is.null(r$klartext)) NULL else as.character(r$klartext))
        if (length(extra)) out$extra <- extra
        out
      })
    )
  })
}

# Traverserar hela uttaget sekventiellt med samma limit tills hasMore = FALSE.
# normalize_page omvandlar en sida till kolumnlistor. Avbrott ger fel – aldrig delresultat.
afr_traverse <- function(entity, normalize_page) {
  path <- if (entity == "je") "/juridiskaenheter/full" else "/arbetsstallen/full"
  field <- if (entity == "je") "jes" else "arbetsstallen"
  pages <- list()
  cursor <- NULL
  repeat {
    q <- list(limit = AFR_PAGE_LIMIT)
    if (!is.null(cursor)) q$cursorId <- cursor
    body <- afr_get(path, q)
    items <- body[[field]] %||% list()
    pages[[length(pages) + 1L]] <- normalize_page(items)
    pg <- body$pagination
    if (is.null(pg) || is.null(pg$hasMore)) stop("AFR-svar saknar pagination.hasMore", call. = FALSE)
    if (!isTRUE(pg$hasMore)) break
    if (is.null(pg$nextCursorId)) stop("AFR-svar saknar nextCursorId trots hasMore", call. = FALSE)
    if (!is.null(cursor) && identical(as.numeric(pg$nextCursorId), as.numeric(cursor))) {
      stop("AFR-cursor står still – avbryter", call. = FALSE)
    }
    cursor <- pg$nextCursorId
    if (length(pages) %% 25 == 0) message(sprintf("%s: %d sidor hämtade", entity, length(pages)))
  }
  list(pages = pages, page_count = length(pages), has_more_false = TRUE)
}
