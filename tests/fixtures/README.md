# UKÄ source reference fixture

`uka-hst-bulk-2026-11-06.zip` contains seven public UKÄ HST CSV exports and their
request/checksum receipts, captured on 2026-11-06, plus the exact export-filter options.
The original metadata hash identifies the full original audit metadata; the included
filter projection deliberately omits the old parent map. Subject paths are checked
against the separately frozen hierarchy in `docs/uka-hst-subject-paths-2026-11-06.json`.

Scopes: Riket, LTU and university 171, 2025/26 and 2016/17, all source genders and ages.
The fixture supports exact comparisons between combined and disjoint university exports
and between CSV and previously captured JSON observations. No new source requests are
permitted in the offline regression check. It is historical evidence, not a current release.

Numeric source observations are unmodified. No total is computed, no empty selection
is filled with zero, and no duplicate key is accepted even if the values differ.

Source URLs and individual CSV hashes are recorded in
`docs/uka-csv-bulk-evidence-2026-11-06.json`.
