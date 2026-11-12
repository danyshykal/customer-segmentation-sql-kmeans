-- =====================================================================
-- 02  Data quality audit (on the raw table)
-- Run each query and screenshot the results for your README.
-- =====================================================================

-- 2.1  One-table summary of every issue
SELECT check_name, rows_affected
FROM (
    SELECT 1 AS n, 'Total rows' AS check_name, COUNT(*) AS rows_affected FROM retail.raw_transactions
    UNION ALL
    SELECT 2, 'Missing customer_id', COUNT(*) FROM retail.raw_transactions WHERE customer_id IS NULL OR customer_id = ''
    UNION ALL
    SELECT 3, 'Missing description', COUNT(*) FROM retail.raw_transactions WHERE description IS NULL OR description = ''
    UNION ALL
    SELECT 4, 'Cancellation rows (invoice C...)', COUNT(*) FROM retail.raw_transactions WHERE invoice LIKE 'C%'
    UNION ALL
    SELECT 5, 'Bad-debt adjustments (invoice A...)', COUNT(*) FROM retail.raw_transactions WHERE invoice LIKE 'A%'
    UNION ALL
    SELECT 6, 'Quantity <= 0', COUNT(*) FROM retail.raw_transactions WHERE quantity::numeric <= 0
    UNION ALL
    SELECT 7, 'Price <= 0', COUNT(*) FROM retail.raw_transactions WHERE price::numeric <= 0
    UNION ALL
    SELECT 8, 'Exact duplicate rows (extra copies)', COUNT(*) - COUNT(DISTINCT raw_transactions.*) FROM retail.raw_transactions
) AS checks
ORDER BY n;

-- 2.2  Non-product stock codes (postage, fees, manual adjustments)
SELECT stock_code,
       MIN(description) AS example_description,
       COUNT(*)         AS row_count
FROM retail.raw_transactions
WHERE stock_code !~ '^[0-9]{5}'
GROUP BY stock_code
ORDER BY row_count DESC
LIMIT 20;

-- 2.3  Largest single lines — spot the 80,995-unit order and its cancellation
SELECT invoice, stock_code, description, quantity::numeric AS qty, price, customer_id, invoice_date
FROM retail.raw_transactions
WHERE ABS(quantity::numeric) > 50000
ORDER BY ABS(quantity::numeric) DESC;

-- 2.4  Date range
SELECT MIN(invoice_date::timestamp) AS first_txn,
       MAX(invoice_date::timestamp) AS last_txn
FROM retail.raw_transactions;
