-- ============================================================
-- Merge staged Jotform rows into dbo.refund_request
-- * TRY_CONVERT on every typed column; rows that cannot be keyed or typed are rejected and logged per row
-- * Insert new submissions, update existing ones (workflow dates and status change over time)
-- * Never deletes: a partial export cannot remove history
-- * Returns staged / rejected / inserted / updated counts to the pipeline
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.usp_merge_refunds
    @run_id VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @staged INT = (SELECT COUNT(*) FROM stg.refund_submissions);

    -- Typed view of staging, one row per staged row
    SELECT
        NULLIF(LTRIM(RTRIM(submission_id)), '')                           AS submission_id,
        TRY_CONVERT(DATETIME2(0), NULLIF(submission_date, ''), 120)        AS submitted_at,
        NULLIF(LTRIM(RTRIM(store)), '')                                    AS store,
        NULLIF(area_coach, '')                                             AS area_coach,
        NULLIF(captured_by, '')                                            AS captured_by,
        NULLIF(customer_name, '')                                          AS customer_name,
        NULLIF(LTRIM(RTRIM(customer_contact)), '')                         AS customer_contact,
        TRY_CONVERT(DATE, NULLIF(transaction_date, ''), 23)                AS transaction_date,
        TRY_CONVERT(DECIMAL(12,2), NULLIF(amount, ''))                     AS amount,
        NULLIF(reason, '')                                                 AS reason,
        NULLIF(LTRIM(RTRIM(card_first6)), '')                              AS card_first6,
        NULLIF(LTRIM(RTRIM(card_last4)), '')                               AS card_last4,
        CASE WHEN NULLIF(LTRIM(RTRIM(bank_statement)), '') IS NULL THEN 0 ELSE 1 END AS has_statement,
        CASE WHEN LTRIM(RTRIM(popia_consent)) = 'Yes' THEN 1 ELSE 0 END    AS popia_consent,
        TRY_CONVERT(DATETIME2(0), NULLIF(recon_reviewed_at, ''), 120)      AS reviewed_at,
        TRY_CONVERT(DATETIME2(0), NULLIF(sent_to_bank_at, ''), 120)        AS sent_to_bank_at,
        TRY_CONVERT(DATETIME2(0), NULLIF(closed_at, ''), 120)              AS closed_at,
        NULLIF(status, '')                                                 AS status,
        submission_id AS raw_id, amount AS raw_amount, submission_date AS raw_submitted
    INTO #typed
    FROM stg.refund_submissions;

    -- Reject reasons, first failing rule wins
    SELECT *,
        CASE
            WHEN submission_id IS NULL                 THEN 'blank submission id'
            WHEN submitted_at IS NULL                  THEN 'submission date not a valid date-time'
            WHEN store IS NULL                         THEN 'store missing'
            WHEN amount IS NULL                        THEN 'amount not numeric'
            WHEN amount <= 0                           THEN 'amount not positive'
        END AS reject_reason
    INTO #checked
    FROM #typed;

    -- Duplicate ids inside one export: keep the latest submission, reject the rest
    ;WITH ranked AS (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY submission_id ORDER BY submitted_at DESC) AS rn
        FROM #checked WHERE reject_reason IS NULL
    )
    UPDATE ranked SET reject_reason = 'duplicate submission id in export' WHERE rn > 1;

    BEGIN TRANSACTION;

    INSERT INTO rpt.refund_reject (run_id, submission_id, reason, raw_amount, raw_submitted)
    SELECT @run_id, raw_id, reject_reason, raw_amount, raw_submitted
    FROM #checked WHERE reject_reason IS NOT NULL;

    DECLARE @actions TABLE (action NVARCHAR(10));

    MERGE dbo.refund_request AS t
    USING (SELECT * FROM #checked WHERE reject_reason IS NULL) AS s
       ON t.submission_id = s.submission_id
    WHEN MATCHED THEN UPDATE SET
        submitted_at = s.submitted_at, store = s.store, area_coach = s.area_coach, captured_by = s.captured_by,
        customer_name = s.customer_name, customer_contact = s.customer_contact, transaction_date = s.transaction_date,
        amount = s.amount, reason = s.reason, card_first6 = s.card_first6, card_last4 = s.card_last4,
        has_statement = s.has_statement, popia_consent = s.popia_consent, reviewed_at = s.reviewed_at,
        sent_to_bank_at = s.sent_to_bank_at, closed_at = s.closed_at, status = s.status,
        last_loaded_at = SYSUTCDATETIME(), last_run_id = @run_id
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (submission_id, submitted_at, store, area_coach, captured_by, customer_name, customer_contact,
         transaction_date, amount, reason, card_first6, card_last4, has_statement, popia_consent,
         reviewed_at, sent_to_bank_at, closed_at, status, last_run_id)
        VALUES (s.submission_id, s.submitted_at, s.store, s.area_coach, s.captured_by, s.customer_name,
         s.customer_contact, s.transaction_date, s.amount, s.reason, s.card_first6, s.card_last4,
         s.has_statement, s.popia_consent, s.reviewed_at, s.sent_to_bank_at, s.closed_at, s.status, @run_id)
    OUTPUT $action INTO @actions;
    -- no WHEN NOT MATCHED BY SOURCE: the load never deletes

    COMMIT TRANSACTION;

    SELECT
        @staged                                                          AS staged,
        (SELECT COUNT(*) FROM #checked WHERE reject_reason IS NOT NULL)  AS rejected,
        (SELECT COUNT(*) FROM @actions WHERE action = 'INSERT')          AS inserted,
        (SELECT COUNT(*) FROM @actions WHERE action = 'UPDATE')          AS updated;
END;
GO
