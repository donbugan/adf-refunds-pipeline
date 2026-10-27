-- ============================================================
-- Business-day calendar for 2026, South African public holidays
-- Weekday holidays only: 21 Mar and 26 Dec fall on Saturdays (not moved);
-- 9 Aug falls on a Sunday and is observed on Monday 10 Aug.
-- ============================================================
DROP TABLE IF EXISTS dbo.calendar;
CREATE TABLE dbo.calendar (
    cal_date        DATE        NOT NULL PRIMARY KEY,
    is_weekend      BIT         NOT NULL,
    holiday_name    NVARCHAR(100) NULL,
    is_business_day BIT         NOT NULL
);
GO

DECLARE @d DATE = '2026-01-01';
WHILE @d <= '2027-01-31'
BEGIN
    INSERT INTO dbo.calendar (cal_date, is_weekend, holiday_name, is_business_day)
    VALUES (@d, CASE WHEN DATEDIFF(DAY, '19000101', @d) % 7 IN (5, 6) THEN 1 ELSE 0 END, NULL, 0);
    SET @d = DATEADD(DAY, 1, @d);
END;
-- 1900-01-01 was a Monday, so DATEDIFF % 7 = 5 is Saturday and 6 is Sunday, whatever DATEFIRST is set to.

UPDATE c SET holiday_name = h.name
FROM dbo.calendar c
JOIN (VALUES
    ('2026-01-01', N'New Year''s Day'),
    ('2026-04-03', N'Good Friday'),
    ('2026-04-06', N'Family Day'),
    ('2026-04-27', N'Freedom Day'),
    ('2026-05-01', N'Workers'' Day'),
    ('2026-06-16', N'Youth Day'),
    ('2026-08-10', N'National Women''s Day (observed)'),
    ('2026-09-24', N'Heritage Day'),
    ('2026-12-16', N'Day of Reconciliation'),
    ('2026-12-25', N'Christmas Day'),
    ('2027-01-01', N'New Year''s Day')
) h(d, name) ON c.cal_date = CAST(h.d AS DATE);

UPDATE dbo.calendar SET is_business_day = CASE WHEN is_weekend = 0 AND holiday_name IS NULL THEN 1 ELSE 0 END;
GO

-- Business days after @from, up to and including @to (0 if @to <= @from)
CREATE OR ALTER FUNCTION dbo.fn_business_days (@from DATE, @to DATE)
RETURNS INT
AS
BEGIN
    RETURN (SELECT COUNT(*) FROM dbo.calendar
            WHERE cal_date > @from AND cal_date <= @to AND is_business_day = 1);
END;
GO

-- Check: 10 weekday holidays in 2026
SELECT COUNT(*) AS weekday_holidays_2026 FROM dbo.calendar
WHERE holiday_name IS NOT NULL AND is_weekend = 0 AND YEAR(cal_date) = 2026;
