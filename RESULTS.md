# Results: Azure run, 27 October 2026

Deployed with `infra/main.bicep` to resource group `rg-refunds` in South Africa North. The database is Azure SQL serverless on the free offer. The pipeline `pl_refunds_to_sql` was run in Debug twice on the shipped file, with as-of date 2026-10-27.

## Load

| Run | Staged | Rejected | Inserted | Updated | Exceptions |
|---|---|---|---|---|---|
| 1st | 307 | 3 | 304 | 0 | 98 |
| 2nd (same file) | 307 | 3 | 0 | 304 | 98 |

The second run inserted nothing and changed no exception counts. The load is idempotent and deletes nothing.

All 307 file rows reached staging, including the fully blank row. ADF did not skip it.

## Rejects

| Reason | Rows |
|---|---|
| blank submission id | 2 (the blank-key row and the fully blank row) |
| amount not numeric | 1 (`R1,200`) |

## Exceptions vs the answer key (`sql/06_validate.sql`)

| Exception | Found | False positives | Missed |
|---|---|---|---|
| BANK_SLA_BREACH | 42 | 0 | 0 |
| CARD_MASK_INVALID | 7 | 0 | 0 |
| MISSING_CONTACT | 4 | 0 | 0 |
| MISSING_STATEMENT | 6 | 0 | 0 |
| NO_POPIA_CONSENT | 2 | 0 | 0 |
| POSSIBLE_DUPLICATE | 4 | 0 | 0 |
| REVIEW_SLA_BREACH | 33 | 0 | 0 |

98 of 98 planted cases were found, with no false positives.

## Deployment notes

- Cloud Shell does not include `sqlcmd`. `infra/run_sql.sh` was run with go-sqlcmd v1.10.0, using `--authentication-method ActiveDirectoryAzCli`. DEPLOY.md now has the install step.
- Datasets and the pipeline were deployed by Bicep straight to the live factory, with no Git connection on the factory.

Screenshots are in `docs/img/`.

## Fix after the first run

The exceptions report described the three `12X4` last-4 entries as "first6 length 6, last4 length 4". The detection was right, but the detail text didn't say what was wrong. The detail now names the failing part (for example "first6 ok, last4 not all digits"). Report dates are also written as `yyyy-mm-dd` without the time part. Neither change affects the counts.
