-- =====================================================================
-- 06  Cluster analysis in SQL (run AFTER the notebook has written
--     retail.customer_clusters back to PostgreSQL)
-- =====================================================================

-- 6.1  Cluster summary with medians
SELECT c.cluster,
       COUNT(*)                                                             AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                   AS pct_customers,
       ROUND(100.0 * SUM(r.monetary) / SUM(SUM(r.monetary)) OVER (), 1)     AS pct_revenue,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY r.recency_days)          AS median_recency_days,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY r.frequency)             AS median_orders,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY r.monetary)::numeric) AS median_spend,
       ROUND(AVG(r.distinct_products))                                      AS avg_distinct_products,
       ROUND(100 * AVG(r.return_rate), 1)                                   AS avg_return_rate_pct
FROM retail.customer_clusters c
JOIN retail.customer_rfm r USING (customer_id)
GROUP BY c.cluster
ORDER BY pct_revenue DESC;


-- 6.2  Top 5 products per cluster
WITH product_rev AS (
    SELECT c.cluster, t.stock_code, MIN(t.description) AS description,
           SUM(t.line_amount) AS net_revenue
    FROM retail.transactions t
    JOIN retail.customer_clusters c USING (customer_id)
    GROUP BY c.cluster, t.stock_code
)
SELECT cluster, rnk, stock_code, description, ROUND(net_revenue) AS net_revenue
FROM (
    SELECT *, RANK() OVER (PARTITION BY cluster ORDER BY net_revenue DESC) AS rnk
    FROM product_rev
) ranked
WHERE rnk <= 5
ORDER BY cluster, rnk;


-- 6.3  UK vs international mix per cluster
SELECT c.cluster,
       ROUND(100.0 * AVG(CASE WHEN r.country = 'United Kingdom' THEN 1 ELSE 0 END), 1) AS pct_uk,
       COUNT(DISTINCT r.country)                                                        AS countries
FROM retail.customer_clusters c
JOIN retail.customer_rfm r USING (customer_id)
GROUP BY c.cluster
ORDER BY pct_uk;


-- 6.4  Revenue at risk: At-Risk Regulars, and how many are still recoverable
SELECT COUNT(*)                                                         AS at_risk_customers,
       ROUND(SUM(r.monetary))                                           AS lifetime_net_revenue,
       COUNT(*) FILTER (WHERE r.recency_days BETWEEN 90 AND 365)        AS recoverable_customers,
       ROUND(SUM(r.monetary) FILTER (WHERE r.recency_days BETWEEN 90 AND 365)) AS recoverable_lifetime_revenue
FROM retail.customer_clusters c
JOIN retail.customer_rfm r USING (customer_id)
WHERE c.cluster = 'At-Risk Regulars';


-- 6.5  Win-back list: top 20 At-Risk Regulars who are still recoverable
--      (last order 90-365 days ago; older than a year is usually too late)
SELECT r.customer_id, r.country, r.last_purchase, r.recency_days,
       r.frequency AS orders, r.monetary AS net_spend, r.rfm_segment
FROM retail.customer_clusters c
JOIN retail.customer_rfm r USING (customer_id)
WHERE c.cluster = 'At-Risk Regulars'
  AND r.recency_days BETWEEN 90 AND 365
ORDER BY r.monetary DESC
LIMIT 20;


-- 6.6  Monthly revenue by cluster in 2011 (who drives the Q4 peak?)
SELECT DATE_TRUNC('month', t.invoice_date)::date                        AS month,
       ROUND(SUM(t.line_amount) FILTER (WHERE c.cluster = 'VIP'))               AS vip,
       ROUND(SUM(t.line_amount) FILTER (WHERE c.cluster = 'Recent Developing')) AS recent_developing,
       ROUND(SUM(t.line_amount) FILTER (WHERE c.cluster = 'At-Risk Regulars'))  AS at_risk_regulars,
       ROUND(SUM(t.line_amount) FILTER (WHERE c.cluster = 'Lost One-Timers'))   AS lost_one_timers
FROM retail.transactions t
JOIN retail.customer_clusters c USING (customer_id)
WHERE t.invoice_date >= '2011-01-01'
GROUP BY 1
ORDER BY 1;
