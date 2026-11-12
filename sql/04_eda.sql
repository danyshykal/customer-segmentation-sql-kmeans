-- =====================================================================
-- 04  Exploratory analysis — business questions in SQL
-- Skills shown: CTEs, aggregates with FILTER, window functions
-- (LAG, SUM OVER, RANK, NTILE), DATE_TRUNC, cohort analysis.
-- Note: Dec 2011 only runs to the 9th — treat it as a partial month.
-- =====================================================================

-- Q1  Headline KPIs
SELECT
    COUNT(DISTINCT customer_id)                                         AS customers,
    COUNT(DISTINCT invoice) FILTER (WHERE NOT is_cancellation)          AS orders,
    ROUND(SUM(line_amount) FILTER (WHERE NOT is_cancellation))          AS gross_revenue,
    ROUND(-SUM(line_amount) FILTER (WHERE is_cancellation))             AS cancelled_value,
    ROUND(SUM(line_amount))                                             AS net_revenue,
    ROUND(100.0 * -SUM(line_amount) FILTER (WHERE is_cancellation)
                / SUM(line_amount) FILTER (WHERE NOT is_cancellation), 1) AS cancel_rate_pct,
    ROUND(SUM(line_amount) FILTER (WHERE NOT is_cancellation)
          / COUNT(DISTINCT invoice) FILTER (WHERE NOT is_cancellation), 2) AS avg_order_value
FROM retail.transactions;


-- Q2  Monthly net revenue, month-over-month growth and running total
WITH monthly AS (
    SELECT DATE_TRUNC('month', invoice_date)::date AS month,
           SUM(line_amount)                        AS net_revenue,
           COUNT(DISTINCT customer_id)             AS active_customers
    FROM retail.transactions
    GROUP BY 1
)
SELECT month,
       ROUND(net_revenue)                                                       AS net_revenue,
       active_customers,
       ROUND(100.0 * (net_revenue - LAG(net_revenue) OVER (ORDER BY month))
                   / LAG(net_revenue) OVER (ORDER BY month), 1)                 AS mom_growth_pct,
       ROUND(SUM(net_revenue) OVER (ORDER BY month))                            AS running_total
FROM monthly
ORDER BY month;


-- Q3  Top 10 countries and their share of revenue
SELECT country,
       COUNT(DISTINCT customer_id)                                   AS customers,
       ROUND(SUM(line_amount))                                       AS net_revenue,
       ROUND(100.0 * SUM(line_amount) / SUM(SUM(line_amount)) OVER (), 1) AS revenue_share_pct
FROM retail.transactions
GROUP BY country
ORDER BY net_revenue DESC
LIMIT 10;


-- Q4  Top 3 products in each of the 5 biggest countries
WITH top_countries AS (
    SELECT country
    FROM retail.transactions
    GROUP BY country
    ORDER BY SUM(line_amount) DESC
    LIMIT 5
),
product_sales AS (
    SELECT t.country, t.stock_code, MIN(t.description) AS description,
           SUM(t.line_amount) AS net_revenue
    FROM retail.transactions t
    JOIN top_countries c USING (country)
    GROUP BY t.country, t.stock_code
),
ranked AS (
    SELECT *, RANK() OVER (PARTITION BY country ORDER BY net_revenue DESC) AS rnk
    FROM product_sales
)
SELECT country, rnk, stock_code, description, ROUND(net_revenue) AS net_revenue
FROM ranked
WHERE rnk <= 3
ORDER BY country, rnk;


-- Q5  How concentrated is revenue? (customers split into 10 equal groups)
WITH customer_rev AS (
    SELECT customer_id, SUM(line_amount) AS net_revenue
    FROM retail.transactions
    GROUP BY customer_id
),
deciles AS (
    SELECT *, NTILE(10) OVER (ORDER BY net_revenue DESC) AS decile
    FROM customer_rev
)
SELECT decile,
       COUNT(*)                                                        AS customers,
       ROUND(SUM(net_revenue))                                         AS net_revenue,
       ROUND(100.0 * SUM(net_revenue) / SUM(SUM(net_revenue)) OVER (), 1) AS share_pct,
       ROUND(100.0 * SUM(SUM(net_revenue)) OVER (ORDER BY decile)
                   / SUM(SUM(net_revenue)) OVER (), 1)                 AS cumulative_share_pct
FROM deciles
GROUP BY decile
ORDER BY decile;


-- Q6  How many times do customers buy?
WITH orders_per_customer AS (
    SELECT customer_id, COUNT(DISTINCT invoice) AS orders
    FROM retail.transactions
    WHERE NOT is_cancellation
    GROUP BY customer_id
)
SELECT CASE WHEN orders = 1  THEN '1 order'
            WHEN orders = 2  THEN '2 orders'
            WHEN orders <= 5 THEN '3-5 orders'
            WHEN orders <= 10 THEN '6-10 orders'
            ELSE '11+ orders' END                                      AS bucket,
       COUNT(*)                                                        AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)              AS pct
FROM orders_per_customer
GROUP BY 1
ORDER BY MIN(orders);


-- Q7  Cohort retention: of customers who first bought in month X,
--     what % bought again 1, 2, 3, 6 and 12 months later?
WITH purchases AS (
    SELECT DISTINCT customer_id, DATE_TRUNC('month', invoice_date)::date AS month
    FROM retail.transactions
    WHERE NOT is_cancellation
),
first_month AS (
    SELECT customer_id, MIN(month) AS cohort
    FROM purchases
    GROUP BY customer_id
),
activity AS (
    SELECT f.cohort,
           p.customer_id,
           (EXTRACT(YEAR FROM AGE(p.month, f.cohort)) * 12
            + EXTRACT(MONTH FROM AGE(p.month, f.cohort)))::int AS month_number
    FROM purchases p
    JOIN first_month f USING (customer_id)
)
SELECT cohort,
       COUNT(DISTINCT customer_id) FILTER (WHERE month_number = 0)  AS cohort_size,
       ROUND(100.0 * COUNT(DISTINCT customer_id) FILTER (WHERE month_number = 1)
             / COUNT(DISTINCT customer_id) FILTER (WHERE month_number = 0), 1) AS m1_pct,
       ROUND(100.0 * COUNT(DISTINCT customer_id) FILTER (WHERE month_number = 2)
             / COUNT(DISTINCT customer_id) FILTER (WHERE month_number = 0), 1) AS m2_pct,
       ROUND(100.0 * COUNT(DISTINCT customer_id) FILTER (WHERE month_number = 3)
             / COUNT(DISTINCT customer_id) FILTER (WHERE month_number = 0), 1) AS m3_pct,
       ROUND(100.0 * COUNT(DISTINCT customer_id) FILTER (WHERE month_number = 6)
             / COUNT(DISTINCT customer_id) FILTER (WHERE month_number = 0), 1) AS m6_pct,
       ROUND(100.0 * COUNT(DISTINCT customer_id) FILTER (WHERE month_number = 12)
             / COUNT(DISTINCT customer_id) FILTER (WHERE month_number = 0), 1) AS m12_pct
FROM activity
WHERE cohort < '2011-01-01'          -- cohorts with at least 11 months of follow-up
GROUP BY cohort
ORDER BY cohort;
