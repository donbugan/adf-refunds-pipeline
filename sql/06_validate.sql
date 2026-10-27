-- ============================================================
-- Validation after a run: counts, rejects, exceptions vs the answer key
-- Run 07_answer_key.sql first to load the planted cases
-- ============================================================
IF OBJECT_ID('rpt.answer_key') IS NULL
CREATE TABLE rpt.answer_key (submission_id VARCHAR(30) NOT NULL, exception_type VARCHAR(40) NOT NULL);
GO

-- Expected for the shipped file: staged 307, rejected 3, merged 304
SELECT TOP 5 * FROM rpt.refund_run ORDER BY run_at DESC;
SELECT reason, COUNT(*) AS rows_rejected FROM rpt.refund_reject
WHERE run_id = (SELECT TOP 1 run_id FROM rpt.refund_run ORDER BY run_at DESC) GROUP BY reason;

-- Detection scorecard: true positives, false positives, missed
SELECT COALESCE(f.exception_type, k.exception_type) AS exception_type,
       SUM(CASE WHEN f.submission_id IS NOT NULL AND k.submission_id IS NOT NULL THEN 1 ELSE 0 END) AS true_pos,
       SUM(CASE WHEN k.submission_id IS NULL THEN 1 ELSE 0 END) AS false_pos,
       SUM(CASE WHEN f.submission_id IS NULL THEN 1 ELSE 0 END) AS missed
FROM rpt.refund_exception f
FULL OUTER JOIN rpt.answer_key k ON k.submission_id = f.submission_id AND k.exception_type = f.exception_type
GROUP BY COALESCE(f.exception_type, k.exception_type)
ORDER BY 1;
