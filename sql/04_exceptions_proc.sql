-- ============================================================
-- Build the exception dataset and the run record
-- SLAs from the store SOP: Recon review within 2 business days; bank within 10 business days
-- An open item counts against its SLA up to @as_of_date
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.usp_build_refund_exceptions
    @run_id     VARCHAR(100),
    @as_of_date DATE = NULL,
    @staged     INT = 0,
    @rejected   INT = 0,
    @inserted   INT = 0,
    @updated    INT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @as_of_date = COALESCE(@as_of_date, CAST(SYSUTCDATETIME() AS DATE));

    BEGIN TRANSACTION;
    DELETE FROM rpt.refund_exception;

    INSERT INTO rpt.refund_exception (submission_id, exception_type, detail, as_of_date, run_id)
    -- Recon review later than 2 business days (or still unreviewed past that)
    SELECT submission_id, 'REVIEW_SLA_BREACH',
           CONCAT(dbo.fn_business_days(CAST(submitted_at AS DATE), COALESCE(CAST(reviewed_at AS DATE), @as_of_date)),
                  ' business days', CASE WHEN reviewed_at IS NULL THEN ' and still open' ELSE '' END),
           @as_of_date, @run_id
    FROM dbo.refund_request
    WHERE dbo.fn_business_days(CAST(submitted_at AS DATE), COALESCE(CAST(reviewed_at AS DATE), @as_of_date)) > 2
    UNION ALL
    -- Bank leg longer than 10 business days (or still open past that)
    SELECT submission_id, 'BANK_SLA_BREACH',
           CONCAT(dbo.fn_business_days(CAST(sent_to_bank_at AS DATE), COALESCE(CAST(closed_at AS DATE), @as_of_date)),
                  ' business days', CASE WHEN closed_at IS NULL THEN ' and still open' ELSE '' END),
           @as_of_date, @run_id
    FROM dbo.refund_request
    WHERE sent_to_bank_at IS NOT NULL
      AND dbo.fn_business_days(CAST(sent_to_bank_at AS DATE), COALESCE(CAST(closed_at AS DATE), @as_of_date)) > 10
    UNION ALL
    SELECT submission_id, 'MISSING_STATEMENT', N'no bank statement uploaded', @as_of_date, @run_id
    FROM dbo.refund_request WHERE has_statement = 0
    UNION ALL
    -- Masking must be exactly 6 digits and 4 digits; anything else may mean more of the card was captured
    SELECT submission_id, 'CARD_MASK_INVALID',
           CONCAT(N'first6 ', CASE WHEN card_first6 IS NULL THEN N'missing'
                                   WHEN LEN(card_first6) <> 6 THEN CONCAT(LEN(card_first6), N' characters')
                                   WHEN card_first6 LIKE '%[^0-9]%' THEN N'not all digits' ELSE N'ok' END,
                  N', last4 ', CASE WHEN card_last4 IS NULL THEN N'missing'
                                   WHEN LEN(card_last4) <> 4 THEN CONCAT(LEN(card_last4), N' characters')
                                   WHEN card_last4 LIKE '%[^0-9]%' THEN N'not all digits' ELSE N'ok' END),
           @as_of_date, @run_id
    FROM dbo.refund_request
    WHERE card_first6 IS NULL OR card_last4 IS NULL
       OR LEN(card_first6) <> 6 OR card_first6 LIKE '%[^0-9]%'
       OR LEN(card_last4) <> 4 OR card_last4 LIKE '%[^0-9]%'
    UNION ALL
    SELECT submission_id, 'MISSING_CONTACT', N'no customer contact number', @as_of_date, @run_id
    FROM dbo.refund_request WHERE customer_contact IS NULL
    UNION ALL
    SELECT submission_id, 'NO_POPIA_CONSENT', N'consent not captured', @as_of_date, @run_id
    FROM dbo.refund_request WHERE popia_consent = 0
    UNION ALL
    -- Same refund submitted more than once: flag every later submission, citing the first
    SELECT r.submission_id, 'POSSIBLE_DUPLICATE', CONCAT(N'same as ', r.first_id), @as_of_date, @run_id
    FROM (
        SELECT submission_id,
               FIRST_VALUE(submission_id) OVER (PARTITION BY store, amount, card_first6, card_last4, transaction_date
                                                ORDER BY submitted_at, submission_id) AS first_id,
               ROW_NUMBER() OVER (PARTITION BY store, amount, card_first6, card_last4, transaction_date
                                  ORDER BY submitted_at, submission_id) AS rn
        FROM dbo.refund_request
    ) r
    WHERE r.rn > 1;

    INSERT INTO rpt.refund_run (run_id, as_of_date, staged, rejected, inserted, updated, exceptions)
    VALUES (@run_id, @as_of_date, @staged, @rejected, @inserted, @updated, (SELECT COUNT(*) FROM rpt.refund_exception));
    COMMIT TRANSACTION;

    SELECT exception_type, COUNT(*) AS cases
    FROM rpt.refund_exception GROUP BY exception_type ORDER BY exception_type;
END;
GO

-- Summary view for Power BI: SLA performance per area coach and month
CREATE OR ALTER VIEW rpt.v_refund_sla_by_area AS
SELECT r.area_coach,
       FORMAT(r.submitted_at, 'yyyy-MM') AS submitted_month,
       COUNT(*)                                                             AS requests,
       SUM(CASE WHEN e1.submission_id IS NULL THEN 1 ELSE 0 END)            AS review_on_time,
       SUM(CASE WHEN e2.submission_id IS NOT NULL THEN 1 ELSE 0 END)        AS bank_breaches,
       SUM(r.amount)                                                        AS amount_requested
FROM dbo.refund_request r
LEFT JOIN rpt.refund_exception e1 ON e1.submission_id = r.submission_id AND e1.exception_type = 'REVIEW_SLA_BREACH'
LEFT JOIN rpt.refund_exception e2 ON e2.submission_id = r.submission_id AND e2.exception_type = 'BANK_SLA_BREACH'
GROUP BY r.area_coach, FORMAT(r.submitted_at, 'yyyy-MM');
GO
