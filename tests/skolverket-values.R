source("R/etl/skolverket_values.R")

values <- skv_exact_number(c("83,4", "100,0", ".", "..", "~100", ""))
stopifnot(isTRUE(all.equal(values[1:2], c(83.4, 100))))
stopifnot(all(is.na(values[3:6])))

gr9 <- data.frame(
  "Skola" = c("Testskolan", "Testskolan"),
  "Skol-enhetskod" = c("12345678", "12345678"),
  "Skolkommun" = c("Luleå", "Luleå"),
  "Kommun-kod" = c("2580", "2580"),
  "Typ av huvudman" = c("Kommunal", "Kommunal"),
  "Kön" = c("Samtliga", "Flickor"),
  "Andel (%) elever behöriga till yrkesprog." = c("88,5", "90,0"),
  check.names = FALSE
)

obs <- skv_parse_gr9(gr9, "2025/26")
stopifnot(length(obs) == 1L)
stopifnot(obs[[1]]$geo_code == "2580")
stopifnot(obs[[1]]$dimensions$skolenhet_code == "12345678")
stopifnot(obs[[1]]$value == 88.5)

throughput <- data.frame(
  "Skolenhet" = "Testgymnasiet",
  "Skolenhets-kod" = "87654321",
  "Kommun" = "Luleå",
  "Kommun-kod" = "2580",
  "Typ av huvudman" = "Kommunal",
  "Program" = "Gymnasieskolan totalt",
  "Genomströmning" = "Andel elever (%) med examen från gymnasieskolan inom 4 år",
  "2021/22" = "80,0",
  "2020/21" = "79,0",
  "2019/20" = "78,0",
  "2018/19" = "77,0",
  "2017/18" = "76,0",
  "2016/17" = "75,0",
  "2015/16" = "74,0",
  "2014/15" = "73,0",
  "2013/14" = "72,0",
  "2012/13" = "71,0",
  check.names = FALSE
)

obs2 <- skv_parse_throughput_series(
  throughput,
  "Andel elever (%) med examen från gymnasieskolan inom 4 år",
  10L
)
stopifnot(length(obs2) == 10L)
stopifnot(length(unique(vapply(obs2, function(x) x$period, character(1)))) == 10L)
skv_validate_observations(obs2, "test", 10L)

message("Skolverket parser/values: OK")
