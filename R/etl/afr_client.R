# Klient för SCB:s Allmänna företagsregister (AFR), API v1.
# API-nyckeln läses endast från miljövariabeln SCB_AFR_API_KEY och skickas
# i headern X-API-Key. Den skrivs aldrig ut, loggas aldrig och sparas aldrig.

suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
})

AFR_PAGE_LIMIT <- 5000L
AFR_API_VERSION <- "v1"

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || (length(x) == 1 && is.na(x))) y else x
}

afr_stats <- new.env()
afr_stats$requests <- 0L
afr_stats$retries <- 0L
afr_stats$http_429 <- 0L
afr_stats$bytes <- 0
afr_stats$throttle_wait_s <- 0
afr_stats$retry_wait_s <- 0

# Proaktiv hastighetsbegränsning: minsta tid mellan två anropsstarter.
# Startvärde via SCB_AFR_MIN_INTERVAL_SEC (standard 3 s ≈ 20 anrop/min).
# Adaptivt: varje 429 fördubblar intervallet (max 60 s) och det sänks sedan
# försiktigt (5 %) efter 50 lyckade anrop i rad, aldrig under startvärdet.
afr_throttle <- new.env()
afr_throttle$base <- max(0.5, suppressWarnings(as.numeric(Sys.getenv("SCB_AFR_MIN_INTERVAL_SEC", "3"))) %||% 3)
afr_throttle$interval <- afr_throttle$base
afr_throttle$last <- 0
afr_throttle$ok_streak <- 0L
afr_throttle$max_interval_seen <- afr_throttle$base

afr_wait_turn <- function() {
  now <- as.numeric(Sys.time())
  wait <- afr_throttle$last + afr_throttle$interval - now
  if (wait > 0) {
    Sys.sleep(wait)
    afr_stats$throttle_wait_s <- afr_stats$throttle_wait_s + wait
  }
  afr_throttle$last <- as.numeric(Sys.time())
}

afr_on_success <- function(resp) {
  afr_throttle$ok_streak <- afr_throttle$ok_streak + 1L
  if (afr_throttle$ok_streak >= 50L && afr_throttle$interval > afr_throttle$base) {
    afr_throttle$interval <- max(afr_throttle$base, afr_throttle$interval * 0.95)
    afr_throttle$ok_streak <- 0L
  }
  # Om SCB skickar kvothuvuden: pausa innan kvoten tar slut i stället för att få 429.
  rem <- suppressWarnings(as.numeric(resp_header(resp, "RateLimit-Remaining") %||%
    resp_header(resp, "X-RateLimit-Remaining") %||% NA))
  reset <- suppressWarnings(as.numeric(resp_header(resp, "RateLimit-Reset") %||%
    resp_header(resp, "X-RateLimit-Reset") %||% NA))
  if (!is.na(rem) && rem <= 1 && !is.na(reset) && reset > 0) {
    # Reset kan vara sekunder kvar eller epoch-sekunder.
    secs <- if (reset > 1e9) reset - as.numeric(Sys.time()) else reset
    secs <- min(600, max(0, secs)) + 1
    message(sprintf("AFR-kvot nästan slut – pausar %.0fs proaktivt", secs))
    Sys.sleep(secs)
    afr_stats$throttle_wait_s <- afr_stats$throttle_wait_s + secs
  }
}

afr_on_429 <- function() {
  afr_throttle$ok_streak <- 0L
  afr_throttle$interval <- min(60, afr_throttle$interval * 2)
  afr_throttle$max_interval_seen <- max(afr_throttle$max_interval_seen, afr_throttle$interval)
  message(sprintf("AFR 429 – nytt minsta intervall %.1fs", afr_throttle$interval))
}

afr_throttle_summary <- function() {
  list(
    base_interval_s = afr_throttle$base,
    final_interval_s = round(afr_throttle$interval, 2),
    max_interval_s = round(afr_throttle$max_interval_seen, 2),
    throttle_wait_s = round(afr_stats$throttle_wait_s),
    retry_wait_s = round(afr_stats$retry_wait_s)
  )
}

afr_base_url <- function() {
  sub("/+$", "", Sys.getenv("SCB_AFR_BASE_URL", unset = "https://apiafr.scb.se"))
}

afr_key <- function() {
  x <- Sys.getenv("SCB_AFR_API_KEY", unset = "")
  if (!nzchar(x)) stop("SCB_AFR_API_KEY saknas", call. = FALSE)
  x
}

# GET med proaktiv hastighetsbegränsning samt retry/backoff på 429, 5xx och
# nätverksfel. Respekterar Retry-After.
afr_get <- function(path, query = list(), max_tries = 8L) {
  url <- paste0(afr_base_url(), "/", AFR_API_VERSION, path)
  for (attempt in seq_len(max_tries)) {
    req <- request(url) |>
      req_headers("X-API-Key" = afr_key(), "Accept" = "application/json") |>
      req_url_query(!!!query) |>
      req_timeout(180) |>
      req_error(is_error = function(resp) FALSE)

    afr_wait_turn()
    afr_stats$requests <- afr_stats$requests + 1L
    resp <- tryCatch(req_perform(req), error = function(e) e)

    if (inherits(resp, "error")) {
      wait <- min(300, 2^attempt)
      message(sprintf("AFR nätverksfel (%s), försök %d – väntar %ds", conditionMessage(resp), attempt, wait))
      afr_stats$retries <- afr_stats$retries + 1L
      afr_stats$retry_wait_s <- afr_stats$retry_wait_s + wait
      Sys.sleep(wait)
      next
    }

    status <- resp_status(resp)
    if (status >= 200 && status < 300) {
      afr_on_success(resp)
      raw <- resp_body_raw(resp)
      afr_stats$bytes <- afr_stats$bytes + length(raw)
      return(fromJSON(rawToChar(raw), simplifyVector = FALSE))
    }

    if (status == 429L || status >= 500L) {
      if (status == 429L) {
        afr_stats$http_429 <- afr_stats$http_429 + 1L
        afr_on_429()
      }
      afr_stats$retries <- afr_stats$retries + 1L
      ra <- suppressWarnings(as.numeric(resp_header(resp, "Retry-After") %||% NA))
      wait <- if (!is.na(ra) && ra >= 0) min(600, ra + 1) else min(300, 2^attempt)
      message(sprintf("AFR HTTP %d på %s, försök %d – väntar %ds", status, path, attempt, wait))
      afr_stats$retry_wait_s <- afr_stats$retry_wait_s + wait
      Sys.sleep(wait)
      next
    }

    stop(sprintf("AFR-anrop misslyckades (HTTP %d) för %s", status, path), call. = FALSE)
  }
  stop(sprintf("AFR-anrop gav upp efter %d försök: %s", max_tries, path), call. = FALSE)
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
