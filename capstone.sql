use capstone;
# Calculate total sales revenue and quantity sold by product category and customer_state.
SELECT 
    p.product_category,
    c.customer_state,
    SUM(oi.price) AS total_revenue,
    COUNT(*) AS total_quantity
FROM order_items oi
JOIN orders o 
    ON oi.order_id = o.order_id
JOIN customers c 
    ON o.customer_id = c.customer_id
JOIN products p 
    ON oi.product_id = p.product_id
GROUP BY p.product_category, c.customer_state
ORDER BY total_revenue DESC;

# Identify the top 5 products by total sales revenue across all Walmart regions.
SELECT 
    p.product_id,
    p.product_category,
    SUM(oi.price) AS total_revenue
FROM order_items oi
JOIN products p 
    ON oi.product_id = p.product_id
JOIN orders o 
    ON oi.order_id = o.order_id
JOIN customers c 
    ON o.customer_id = c.customer_id
GROUP BY p.product_id, p.product_category
ORDER BY total_revenue DESC
LIMIT 5;

#Find customers with the highest number of orders and total spend, ranking them as Walmart’s most valuable customers.
SELECT 
    c.customer_id,
    COUNT(DISTINCT o.order_id) AS total_orders,
    SUM(oi.price) AS total_spend
FROM customers c
JOIN orders o 
    ON c.customer_id = o.customer_id
JOIN order_items oi 
    ON o.order_id = oi.order_id
GROUP BY c.customer_id
ORDER BY total_spend DESC, total_orders DESC
LIMIT 10;

# Determine customer states with the highest average order value (AOV).
SELECT 
    c.customer_state,
    round(sum(oi.price) / COUNT(DISTINCT o.order_id),2) AS avg_order_value
FROM customers c
JOIN orders o 
    ON c.customer_id = o.customer_id
JOIN order_items oi 
    ON o.order_id = oi.order_id
GROUP BY c.customer_state
ORDER BY avg_order_value DESC;

# Compute average delivery time (in days) by seller state, calculated as the difference between order_purchase_timestamp and order_delivered_customer_date.
SELECT 
    s.seller_state,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)), 2) AS avg_delivery_days
FROM orders o
JOIN order_items oi 
    ON o.order_id = oi.order_id
JOIN sellers s 
    ON oi.seller_id = s.seller_id
WHERE o.order_delivered_customer_date IS NOT NULL
  AND o.order_purchase_timestamp IS NOT NULL
GROUP BY s.seller_state
ORDER BY avg_delivery_days ASC;

#List the top 5 sellers based on total revenue earned.
SELECT 
    s.seller_id,
    s.seller_state,
    SUM(oi.price) AS total_revenue
FROM order_items oi
JOIN sellers s 
    ON oi.seller_id = s.seller_id
GROUP BY s.seller_id, s.seller_state
ORDER BY total_revenue DESC
LIMIT 5;

#Analyze the monthly revenue trend over the last 12 months to track Walmart’s growth.
SELECT 
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
   round(SUM(oi.price),2) AS total_revenue
FROM orders o
JOIN order_items oi 
    ON o.order_id = oi.order_id
GROUP BY order_month
ORDER BY order_month;

# Calculate the number of new unique customers acquired each month, based on customer_unique_id.
WITH first_orders AS (
    SELECT 
        c.customer_unique_id,
        MIN(o.order_purchase_timestamp) AS first_order_date
    FROM orders o
    JOIN customers c 
        ON o.customer_id = c.customer_id
    WHERE o.order_purchase_timestamp IS NOT NULL
    GROUP BY c.customer_unique_id
)
SELECT 
    DATE_FORMAT(first_order_date, '%Y-%m') AS order_month,
    COUNT(DISTINCT customer_unique_id) AS new_customers
FROM first_orders
GROUP BY order_month
ORDER BY order_month;

#Rank customers by lifetime spend within each customer state using SQL window functions.
CREATE TEMPORARY TABLE geo_state AS
SELECT 
    geolocation_zip_code_prefix,
    MAX(geolocation_state) AS geolocation_state
FROM geolocation
GROUP BY geolocation_zip_code_prefix;

CREATE TEMPORARY TABLE customer_spend AS
SELECT 
    c.customer_id,
    g.geolocation_state AS customer_state,
    SUM(p.payment_value) AS lifetime_spend
FROM customers c
JOIN orders o 
    ON c.customer_id = o.customer_id
JOIN payments p 
    ON o.order_id = p.order_id
JOIN geo_state g 
    ON c.customer_zip_code_prefix = g.geolocation_zip_code_prefix
GROUP BY c.customer_id, g.geolocation_state;

SET @rank := 0;
SET @state := '';

SELECT *
FROM (
    SELECT
        customer_id,
        customer_state,
        lifetime_spend,
        @rank := IF(@state = customer_state, @rank + 1, 1) AS rank_in_state,
        @state := customer_state
    FROM customer_spend
    ORDER BY customer_state, lifetime_spend DESC
) ranked
WHERE rank_in_state <= 10;

#Compute the rolling 3-month average revenue trend, to visualize sales momentum.
SELECT
    m1.year_months,
    m1.monthly_revenue,
    ROUND(AVG(m2.monthly_revenue), 2) AS rolling_3m_avg
FROM (
    SELECT 
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS year_months,
        SUM(p.payment_value) AS monthly_revenue
    FROM orders o
    JOIN payments p 
        ON o.order_id = p.order_id
    GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
) m1
JOIN (
    SELECT 
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS year_months,
        SUM(p.payment_value) AS monthly_revenue
    FROM orders o
    JOIN payments p 
        ON o.order_id = p.order_id
    GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
) m2
  ON m2.year_months BETWEEN DATE_FORMAT(DATE_SUB(CONCAT(m1.year_months, '-01'), INTERVAL 2 MONTH), '%Y-%m')
                      AND m1.year_months
GROUP BY m1.year_months, m1.monthly_revenue
ORDER BY m1.year_months;
