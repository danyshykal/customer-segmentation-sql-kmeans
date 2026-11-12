-- =====================================================================
-- 03  Clean transactions table
-- Rules (each one is a decision — see README "Data cleaning decisions"):
--   1. Remove exact duplicate rows
--   2. Cast TEXT columns to proper types
--   3. Keep only rows with a customer_id (can't segment anonymous buyers)
--   4. Keep only price > 0 (drop free samples / damaged-stock write-offs)
--   5. Drop bad-debt adjustments (invoice 'A...')
--   6. Drop non-product codes (postage, fees, manual adjustments, vouchers, tests)
--   7. KEEP cancellations (invoice 'C...', negative qty) so revenue can be NETTED
-- =====================================================================

DROP TABLE IF EXISTS retail.transactions CASCADE;

CREATE TABLE retail.transactions AS
WITH dedup AS (
    SELECT DISTINCT *
    FROM retail.raw_transactions
),
typed AS (
    SELECT
        invoice,
        stock_code,
        TRIM(description)                        AS description,
        quantity::numeric::int                   AS quantity,
        invoice_date::timestamp                  AS invoice_date,
        price::numeric(12, 3)                    AS price,
        NULLIF(customer_id, '')::numeric::int    AS customer_id,   -- handles '13085' and '13085.0'
        country
    FROM dedup
)
SELECT
    invoice,
    stock_code,
    description,
    quantity,
    invoice_date,
    price,
    customer_id,
    country,
    invoice LIKE 'C%'                            AS is_cancellation,
    ROUND(quantity * price, 2)                   AS line_amount
FROM typed
WHERE customer_id IS NOT NULL
  AND price > 0
  AND invoice NOT LIKE 'A%'
  AND stock_code NOT IN ('POST', 'DOT', 'M', 'm', 'C2', 'D', 'S', 'B',
                         'BANK CHARGES', 'ADJUST', 'ADJUST2', 'AMAZONFEE', 'PADS', 'CRUK')
  AND stock_code !~* '^(gift_|test)';

CREATE INDEX idx_txn_customer ON retail.transactions (customer_id);
CREATE INDEX idx_txn_date     ON retail.transactions (invoice_date);

-- Checkpoints
SELECT COUNT(*)                                        AS clean_rows,
       COUNT(DISTINCT customer_id)                     AS customers,
       COUNT(DISTINCT invoice) FILTER (WHERE NOT is_cancellation) AS purchase_invoices,
       COUNT(*) FILTER (WHERE is_cancellation)         AS cancellation_rows,
       ROUND(SUM(line_amount))                         AS net_revenue_gbp
FROM retail.transactions;
