-- ============================================================
-- Least privilege for the factory's managed identity
-- Run as the Entra admin of the database. Replace adf-refunds-<you> with your factory name.
-- ============================================================
CREATE USER [adf-refunds-<you>] FROM EXTERNAL PROVIDER;

-- Staging: the copy activity truncates and writes
GRANT SELECT, INSERT, DELETE, ALTER ON SCHEMA::stg TO [adf-refunds-<you>];   -- ALTER is needed for TRUNCATE

-- Only the two procedures; no direct writes to dbo or rpt
GRANT EXECUTE ON OBJECT::dbo.usp_merge_refunds TO [adf-refunds-<you>];
GRANT EXECUTE ON OBJECT::dbo.usp_build_refund_exceptions TO [adf-refunds-<you>];

-- The two report copy activities read the results
GRANT SELECT ON SCHEMA::rpt TO [adf-refunds-<you>];
GRANT SELECT ON OBJECT::dbo.refund_request TO [adf-refunds-<you>];

-- Report readers (Power BI) see rpt only
-- CREATE USER [powerbi-reader] FROM EXTERNAL PROVIDER;
-- GRANT SELECT ON SCHEMA::rpt TO [powerbi-reader];
