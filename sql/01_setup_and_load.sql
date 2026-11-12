-- =====================================================================
-- 01  Setup + load raw data
-- Database: customer_segmentation   Schema: retail
-- Every column is loaded as TEXT first ("staging"), so a bad value
-- never stops the import. Types are fixed in 02_clean.sql.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS retail;

DROP TABLE IF EXISTS retail.raw_transactions CASCADE;
CREATE TABLE retail.raw_transactions (
    invoice       TEXT,
    stock_code    TEXT,
    description   TEXT,
    quantity      TEXT,
    invoice_date  TEXT,
    price         TEXT,
    customer_id   TEXT,
    country       TEXT
);

-- ---------------------------------------------------------------------
-- LOAD THE CSV — pick ONE way:
--
-- (a) pgAdmin: right-click retail.raw_transactions → Import/Export Data
--     Import · Filename: online_retail_II.csv · Format: csv
--     Options tab: Header ON · Delimiter , · Quote " · Encoding UTF8
--
-- (b) psql (SQL Shell), change the path to yours:
--     \copy retail.raw_transactions FROM 'D:/path/to/data/online_retail_II.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
-- ---------------------------------------------------------------------

-- Checkpoint: should return 1,067,371
SELECT COUNT(*) AS raw_rows FROM retail.raw_transactions;
