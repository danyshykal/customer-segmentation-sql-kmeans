-- =====================================================================
-- 05  RFM features + rule-based segments
--   Recency   = days since last purchase (as of 2011-12-10, the day after the data ends)
--   Frequency = number of distinct purchase invoices
--   Monetary  = NET revenue (purchases minus cancellations)
-- Extra features for clustering/profiling: tenure, AOV, products, return rate.
-- =====================================================================

DROP TABLE IF EXISTS retail.customer_rfm CASCADE;

CREATE TABLE retail.customer_rfm AS
WITH params AS (
    SELECT DATE '2011-12-10' AS snapshot_date
),
customer_base AS (
    SELECT
        customer_id,
        MIN(country)                                                    AS country,
        MIN(invoice_date) FILTER (WHERE NOT is_cancellation)            AS first_purchase,
        MAX(invoice_date) FILTER (WHERE NOT is_cancellation)            AS last_purchase,
        COUNT(DISTINCT invoice) FILTER (WHERE NOT is_cancellation)      AS frequency,
        SUM(line_amount)                                                AS monetary,
        SUM(line_amount) FILTER (WHERE NOT is_cancellation)             AS gross_spend,
        COALESCE(-SUM(line_amount) FILTER (WHERE is_cancellation), 0)   AS cancelled_spend,
        COUNT(DISTINCT stock_code) FILTER (WHERE NOT is_cancellation)   AS distinct_products
    FROM retail.transactions
    GROUP BY customer_id
),
features AS (
    SELECT
        b.customer_id,
        b.country,
        b.first_purchase::date,
        b.last_purchase::date,
        (p.snapshot_date - b.last_purchase::date)                       AS recency_days,
        b.frequency,
        ROUND(b.monetary, 2)                                            AS monetary,
        (b.last_purchase::date - b.first_purchase::date)                AS tenure_days,
        ROUND(b.gross_spend / b.frequency, 2)                           AS avg_order_value,
        b.distinct_products,
        ROUND(b.cancelled_spend / b.gross_spend, 4)                     AS return_rate
    FROM customer_base b
    CROSS JOIN params p
    WHERE b.frequency >= 1          -- has at least one real purchase
      AND b.monetary > 0            -- net spend positive (excludes fully-cancelled customers)
),
scored AS (
    SELECT
        f.*,
        NTILE(5) OVER (ORDER BY recency_days DESC)                      AS r_score,  -- most recent = 5
        CASE WHEN frequency = 1  THEN 1                                 -- frequency has many ties,
             WHEN frequency = 2  THEN 2                                 -- so business thresholds are
             WHEN frequency <= 4 THEN 3                                 -- used instead of NTILE
             WHEN frequency <= 9 THEN 4
             ELSE 5 END                                                 AS f_score,
        NTILE(5) OVER (ORDER BY monetary)                               AS m_score   -- highest = 5
    FROM features f
)
SELECT
    s.*,
    CONCAT(r_score, f_score, m_score)                                   AS rfm_code,
    CASE
        WHEN r_score >= 4 AND f_score >= 4             THEN 'Champions'
        WHEN r_score  = 3 AND f_score >= 4             THEN 'Loyal'
        WHEN r_score >= 4 AND f_score BETWEEN 2 AND 3  THEN 'Potential Loyalists'
        WHEN r_score >= 4 AND f_score  = 1             THEN 'New Customers'
        WHEN r_score  = 3 AND f_score <= 3             THEN 'Need Attention'
        WHEN r_score <= 2 AND f_score  = 5             THEN 'Cannot Lose Them'
        WHEN r_score <= 2 AND f_score BETWEEN 3 AND 4  THEN 'At Risk'
        WHEN r_score  = 2 AND f_score <= 2             THEN 'Hibernating'
        ELSE                                                'Lost'
    END                                                                 AS rfm_segment
FROM scored s;

ALTER TABLE retail.customer_rfm ADD PRIMARY KEY (customer_id);

-- Checkpoint: number of customers
SELECT COUNT(*) AS customers FROM retail.customer_rfm;

-- Segment summary
SELECT rfm_segment,
       COUNT(*)                                                    AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)          AS pct_customers,
       ROUND(AVG(recency_days))                                    AS avg_recency_days,
       ROUND(AVG(frequency), 1)                                    AS avg_frequency,
       ROUND(AVG(monetary))                                        AS avg_monetary,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_revenue
FROM retail.customer_rfm
GROUP BY rfm_segment
ORDER BY pct_revenue DESC;
