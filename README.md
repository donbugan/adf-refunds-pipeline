# Card refunds: Jotform export to Azure SQL with Azure Data Factory

Stores capture card-refund requests on a Jotform form. Recon reviews each request, sends it to the bank, and closes it when the bank responds. The form export is a flat CSV, so nobody can see which requests are stuck, which break the SLA, or which were captured badly.

This repo loads that export into Azure SQL with Azure Data Factory and produces an exception list per run.

**All data here is synthetic** (`gen/gen_refunds.py`, seeded). Names, phone numbers, stores and amounts are invented. Card data is masked by design: only the first 6 and last 4 digits exist, never a full card number.

## What the pipeline does

```
Blob: refunds/inbound/jotform_refunds_export.csv
  │
  ├─ Check file          Get Metadata: exists, size > 0, 18 columns. Otherwise Fail, nothing loaded.
  ├─ Stage as text       Copy every column as text into stg.refund_submissions (truncated first).
  ├─ Merge               dbo.usp_merge_refunds: TRY_CONVERT each column, reject rows that cannot be keyed
  │                      or typed (logged per row with a reason), MERGE the rest. Never deletes.
  │                      Returns staged / rejected / inserted / updated.
  ├─ Rows reconcile      rows copied = staged = rejected + inserted + updated, or the run fails.
  ├─ Build exceptions    dbo.usp_build_refund_exceptions: SLA and data-quality rules, as of a given date.
  └─ Reports             refunds/reports/refund_exceptions_<date>.csv and refund_run_<runid>.csv
```

Both connections use the factory's managed identity. No keys or passwords are stored anywhere.

## Exception rules

| Exception | Rule |
|---|---|
| REVIEW_SLA_BREACH | Recon review more than 2 business days after submission (or still unreviewed past that) |
| BANK_SLA_BREACH | More than 10 business days between sent to bank and closed (or still open past that) |
| MISSING_STATEMENT | No bank statement uploaded |
| CARD_MASK_INVALID | First 6 is not exactly 6 digits, or last 4 is not exactly 4 digits |
| MISSING_CONTACT | No customer contact number |
| NO_POPIA_CONSENT | Consent not captured |
| POSSIBLE_DUPLICATE | Same store, amount, card first 6 and last 4, and transaction date as an earlier submission |

Business days exclude weekends and South African public holidays (`dbo.calendar`, 2026). Days are counted after the start date up to and including the end date.

## Expected results for the shipped file (as of 2026-10-27)

| | Rows |
|---|---|
| Read from file | 307 |
| Rejected | 3 (blank submission id, amount `R1,200`, fully blank row) |
| Merged | 304 (all inserts on the first run, all updates on a rerun) |

| Exception | Cases |
|---|---|
| BANK_SLA_BREACH | 42 |
| CARD_MASK_INVALID | 7 |
| MISSING_CONTACT | 4 |
| MISSING_STATEMENT | 6 |
| NO_POPIA_CONSENT | 2 |
| POSSIBLE_DUPLICATE | 4 |
| REVIEW_SLA_BREACH | 33 |

`data/answer_key.csv` lists every planted case. `sql/06_validate.sql` scores the run against it (true positives, false positives, missed).

## What has been tested

It has been deployed and run in Azure (27 October 2026):
- **Load:** 307 rows staged, 3 rejected, 304 merged.
- **Rerun:** 0 inserted and 304 updated.
- **Exceptions:** all 98 planted cases found, with 0 false positives.

Full results are in [`RESULTS.md`](RESULTS.md). The exception rules are also checked locally against the answer key with DuckDB (`tests/check_rules_duckdb.py`).

## Deploy

**Step by step: `docs/DEPLOY.md`.** `infra/main.bicep` deploys every Azure resource in one command, and `infra/run_sql.sh` creates the database objects.

**By hand in the portal:**


1. **Resource group, storage, SQL.** Create a storage account with a container `refunds` (folders `inbound`, `reports`). Create an Azure SQL Database (serverless or Basic is enough) with Microsoft Entra admin set to yourself.
2. **SQL objects.** Run `sql/01` to `sql/04` in order in the query editor.
3. **Factory.** Create a Data Factory (system-assigned managed identity is on by default).
4. **Permissions.**
   - Storage account → Access control → add role **Storage Blob Data Contributor** for the factory's identity (it reads `inbound` and writes `reports`).
   - SQL: replace `adf-refunds-<you>` in `sql/05_security.sql` with the factory name and run it.
   - SQL server → Networking: allow Azure services to access the server.
5. **Factory objects.** Connect the factory to this GitHub repo (Manage → Git configuration, root folder `/adf`), or create the linked services, datasets and pipeline from the JSON files. Replace `<storageaccount>`, `<sqlserver>` and `<database>`.
6. **Run.** Upload `data/jotform_refunds_export.csv` to `refunds/inbound`, then Debug `pl_refunds_to_sql`. Check the counts above, then run `sql/06_validate.sql`.
7. **Clean up.** Delete the resource group when finished.

## Repo layout

```
gen/gen_refunds.py          synthetic export + answer key (seeded)
data/                       jotform_refunds_export.csv, answer_key.csv
sql/01_schema.sql           stg / dbo / rpt tables
sql/02_calendar.sql         business-day calendar, fn_business_days
sql/03_merge_proc.sql       usp_merge_refunds
sql/04_exceptions_proc.sql  usp_build_refund_exceptions, rpt.v_refund_sla_by_area
sql/05_security.sql         least-privilege grants for the factory identity
sql/06_validate.sql         run checks and scorecard against the answer key
infra/main.bicep            all Azure resources and factory objects as code
adf/                        linked services, datasets, pipeline (ADF Git layout)
tests/check_rules_duckdb.py local check of the exception rules
docs/decisions.md           why it is built this way
```
