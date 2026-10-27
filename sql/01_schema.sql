-- ============================================================
-- Card refunds: schemas and tables (Azure SQL Database)
-- stg  = raw text copy of the Jotform export, truncated each run
-- dbo  = typed, merged refund requests (never deleted by the load)
-- rpt  = exceptions and run reports
-- ============================================================
IF SCHEMA_ID('stg') IS NULL EXEC('CREATE SCHEMA stg');
IF SCHEMA_ID('rpt') IS NULL EXEC('CREATE SCHEMA rpt');
GO

DROP TABLE IF EXISTS stg.refund_submissions;
CREATE TABLE stg.refund_submissions (
    submission_id       NVARCHAR(100) NULL,
    submission_date     NVARCHAR(100) NULL,
    store               NVARCHAR(200) NULL,
    area_coach          NVARCHAR(200) NULL,
    captured_by         NVARCHAR(200) NULL,
    customer_name       NVARCHAR(200) NULL,
    customer_contact    NVARCHAR(100) NULL,
    transaction_date    NVARCHAR(100) NULL,
    amount              NVARCHAR(100) NULL,
    reason              NVARCHAR(400) NULL,
    card_first6         NVARCHAR(50)  NULL,
    card_last4          NVARCHAR(50)  NULL,
    bank_statement      NVARCHAR(400) NULL,
    popia_consent       NVARCHAR(50)  NULL,
    recon_reviewed_at   NVARCHAR(100) NULL,
    sent_to_bank_at     NVARCHAR(100) NULL,
    closed_at           NVARCHAR(100) NULL,
    status              NVARCHAR(100) NULL
);
GO

IF OBJECT_ID('dbo.refund_request') IS NULL
CREATE TABLE dbo.refund_request (
    submission_id       VARCHAR(30)    NOT NULL PRIMARY KEY,
    submitted_at        DATETIME2(0)   NOT NULL,
    store               NVARCHAR(200)  NOT NULL,
    area_coach          NVARCHAR(200)  NULL,
    captured_by         NVARCHAR(200)  NULL,
    customer_name       NVARCHAR(200)  NULL,
    customer_contact    VARCHAR(20)    NULL,
    transaction_date    DATE           NULL,
    amount              DECIMAL(12,2)  NOT NULL CHECK (amount > 0),
    reason              NVARCHAR(400)  NULL,
    card_first6         VARCHAR(10)    NULL,   -- masked by design: never a full card number
    card_last4          VARCHAR(10)    NULL,
    has_statement       BIT            NOT NULL,
    popia_consent       BIT            NOT NULL,
    reviewed_at         DATETIME2(0)   NULL,
    sent_to_bank_at     DATETIME2(0)   NULL,
    closed_at           DATETIME2(0)   NULL,
    status              NVARCHAR(100)  NULL,
    first_loaded_at     DATETIME2(0)   NOT NULL DEFAULT SYSUTCDATETIME(),
    last_loaded_at      DATETIME2(0)   NOT NULL DEFAULT SYSUTCDATETIME(),
    last_run_id         VARCHAR(100)   NULL
);
GO

-- Per-row reject log: every row that cannot be loaded, with the reason and the run that saw it
IF OBJECT_ID('rpt.refund_reject') IS NULL
CREATE TABLE rpt.refund_reject (
    reject_id       INT IDENTITY(1,1) PRIMARY KEY,
    run_id          VARCHAR(100)   NOT NULL,
    submission_id   NVARCHAR(100)  NULL,
    reason          VARCHAR(200)   NOT NULL,
    raw_amount      NVARCHAR(100)  NULL,
    raw_submitted   NVARCHAR(100)  NULL,
    logged_at       DATETIME2(0)   NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- Exceptions found on the latest run (rebuilt each run)
IF OBJECT_ID('rpt.refund_exception') IS NULL
CREATE TABLE rpt.refund_exception (
    submission_id   VARCHAR(30)    NOT NULL,
    exception_type  VARCHAR(40)    NOT NULL,
    detail          NVARCHAR(400)  NULL,
    as_of_date      DATE           NOT NULL,
    run_id          VARCHAR(100)   NOT NULL,
    CONSTRAINT pk_refund_exception PRIMARY KEY (submission_id, exception_type)
);
GO

-- One row per pipeline run: the reconciliation record
IF OBJECT_ID('rpt.refund_run') IS NULL
CREATE TABLE rpt.refund_run (
    run_id          VARCHAR(100)   NOT NULL PRIMARY KEY,
    run_at          DATETIME2(0)   NOT NULL DEFAULT SYSUTCDATETIME(),
    as_of_date      DATE           NOT NULL,
    staged          INT            NOT NULL,
    rejected        INT            NOT NULL,
    inserted        INT            NOT NULL,
    updated         INT            NOT NULL,
    exceptions      INT            NOT NULL
);
GO
