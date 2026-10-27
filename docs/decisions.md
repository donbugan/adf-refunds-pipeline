# Decisions

**Stage everything as text.** The export is typed by people. A Copy activity that converts types fails the whole file on one bad amount. Staging as text loads every row, and the merge procedure decides row by row with TRY_CONVERT.

**Reject per row, with a reason.** A bad row is logged in `rpt.refund_reject` with the run id, raw values and the rule it failed. The rest of the file still loads. Someone can fix the form entry and the next export picks it up.

**Never delete in the load.** The MERGE has no `WHEN NOT MATCHED BY SOURCE`. A partial or filtered export cannot wipe history.

**Reconcile counts or fail.** Rows copied must equal rows staged, and staged must equal rejected + inserted + updated. If they do not match, the run fails instead of reporting numbers that do not add up.

**Guard the file before loading.** A missing, empty or reshaped export (someone added a form field) stops the run before staging is truncated against it.

**Business days from a calendar table.** SLA counts use `dbo.calendar` with South African public holidays, not DATEDIFF on weekdays. 10 August 2026 is in it because Women's Day fell on a Sunday.

**As-of date is a parameter.** The exception rules count open items up to `asOfDate`. Reruns for a past date give the same answer, and the shipped file can be checked against its answer key.

**Card data stays masked.** Only first 6 and last 4 digits are stored. `CARD_MASK_INVALID` flags entries that do not fit that shape, because an over-long value can mean more of the card number was captured than should have been.

**Managed identity, least privilege.** No keys or passwords in the factory. In SQL, the factory identity can write to `stg`, execute the two procedures, and read results. It has no direct write access to `dbo` or `rpt`.
