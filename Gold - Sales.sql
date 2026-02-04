select * from gold_sales
limit 10;

select order_date, sum(sales_amount ) as tot_sales
from gold_sales
where order_date is not null
AND order_date <> '' #to avoid empty cells
group by order_date
order by order_date
;

-- Find sales by year
select year(order_date), sum(sales_amount ) as tot_sales
from gold_sales
where order_date is not null
AND order_date <> '' #to avoid empty cells
group by year(order_date)
order by year(order_date)
;

select year(order_date), count(distinct customer_key) as num_customers, sum(sales_amount ) as tot_sales, 
sum(quantity) as tot_quantity
from gold_sales
where order_date is not null
AND order_date <> '' #to avoid empty cells
group by year(order_date)
order by year(order_date)
;

-- See the monthly trends
select month(order_date), count(distinct customer_key) as num_customers, sum(sales_amount) as tot_sales, sum(quantity) as tot_quantity
from gold_sales
where order_date is not null
AND order_date <> '' #to avoid empty cells
group by month(order_date)
order by sum(sales_amount) desc
;

-- Calculate the total sales per month
select * from gold_sales
limit 10;

select date_format(order_date, '%Y-%m') as order_month, sum(sales_amount) as tot_sales
from gold_sales
where order_date is not null AND order_date <> ''
group by order_month
order by order_month
;

-- Running total per month across all the years
select order_month, tot_sales, sum(tot_sales) over(order by order_month) as running_tot_sales
from
(select date_format(order_date, '%Y-%m') as order_month, sum(sales_amount) as tot_sales
from gold_sales
where order_date is not null AND order_date <> ''
group by order_month
order by order_month) t
;

-- Restart the running total each year
select order_year, month(order_month) as order_month, tot_sales, 
sum(tot_sales) over(partition by order_year order by order_month) as running_tot_sales
from
(select 
year(order_date) as order_year,
cast(date_format(order_date, '%Y-%m-01') as date) as order_month, 
sum(sales_amount) as tot_sales
from gold_sales
where order_date is not null AND order_date <> ''
group by year(order_date), cast(date_format(order_date, '%Y-%m-01') as date)
order by order_month) t
order by order_year, order_month
;

-- Compare yearly sales of the products to the average performance and the previous year's sales (create these two new columns)
select * from gold_sales
limit 10;

select * from gold_products
limit 10;

with yearly_product_sales as
(select 
year(s.order_date) as order_year, p.product_name, sum(s.sales_amount) as tot_sales
from gold_sales s
left join gold_products p
on s.product_key = p.product_key
where s.order_date is not null and s.order_date <> ''
group by year(s.order_date), p.product_name)
select *, avg(tot_sales) over(partition by product_name) avg_sales, # make new avg column
tot_sales - avg(tot_sales) over(partition by product_name) as diff_avg, # difference between avg sale and tot sales
case # flag column
when tot_sales - avg(tot_sales) over(partition by product_name) < 0 then 'below avg'
when tot_sales - avg(tot_sales) over(partition by product_name) > 0 then 'above avg'
else 'avg' end as note,
lag(tot_sales) over(partition by product_name order by order_year) prev_year, # column to show the previous year sales next to the current one
tot_sales - lag(tot_sales) over(partition by product_name order by order_year) as diff_prev,
case
when tot_sales - lag(tot_sales) over(partition by product_name order by order_year) > 0 then 'increase'
when tot_sales - lag(tot_sales) over(partition by product_name order by order_year) < 0 then 'decrease'
else 'no change' end as note
from yearly_product_sales
order by product_name, order_year
;

-- Which categories contribute most to the total sales?
select * from gold_sales
limit 10;

select * from gold_products
limit 10;

with sales_cat as
(select category, sum(sales_amount) as tot_sales
from gold_sales s
left join gold_products p
on s.product_key = p.product_key
where s.order_date is not null and s.order_date <> ''
group by category
order by tot_sales desc)
select *, sum(tot_sales) over() as sum, # new sum column
concat(round(tot_sales / sum(tot_sales) over() * 100, 2), '%') as tot_percentage # new % column
from sales_cat
;

-- How many products fall in each cost segment
select * from gold_products
order by cost;

with product_segment as
(select product_key, product_name, cost,
case 
when cost < 100 then 'below 100'
when cost < 500 then '100-500'
when cost < 1000 then '500-1000'
else 'above 1000' end as cost_range
from gold_products)
select cost_range, count(product_name) as tot_products
from product_segment
group by cost_range
;

-- group customers in 3 categories based on spending behavior, lifespan analysis
select * from gold_sales
limit 10;

select * from gold_products
limit 10;

select * from gold_customers
limit 10;

with customer_spending as (
select c.customer_key, sum(s.sales_amount) as tot_sales, min(order_date) as min_date, max(order_date) as max_date,
timestampdiff(month, min(order_date), max(order_date)) as lifespan_months
from gold_sales s
left join gold_customers c
on s.customer_key = c.customer_key
group by customer_key
)
select 
case
when lifespan_months >=12 and tot_sales > 5000 then 'vip'
when lifespan_months >=12 and tot_sales < 5000 then 'regular'
else 'new' end as label,
count(distinct customer_key) as num_customers
from customer_spending
group by label
order by num_customers desc
;

-- Report about customers metrics and behaviors
create view gold.report_customers as
with base_query as (
-- 1. retrieve core columns
select order_number, product_key, order_date, sales_amount, quantity, s.customer_key, customer_number, 
concat(first_name, ' ', last_name) as full_name, 
timestampdiff(year, birthdate, curdate()) as age
from gold_sales s
left join gold_customers c
on s.customer_key = c.customer_key
where order_date is not null
)
, customer_aggregation as
-- 2. summarise key metrics at customer level
(select customer_key, customer_number, full_name, age,
count(distinct order_number) as tot_orders,
sum(sales_amount) as tot_sales,
sum(quantity) as tot_quantity,
count(distinct product_key) as tot_products,
max(order_date) as last_order_date,
timestampdiff(month, min(order_date), max(order_date)) as lifespan_months
from base_query
group by customer_key, customer_number, full_name, age
)
-- 3. create categories
select customer_key, customer_number, full_name, 
age, 
case
when age < 20 then '<20'
when age < 30 then '20-29'
when age < 40 then '30-39'
when age < 50 then '40-49'
else '50 and above' end as age_range
,case
when lifespan_months >=12 and tot_sales > 5000 then 'vip'
when lifespan_months >=12 and tot_sales < 5000 then 'regular'
else 'new' end as label,
timestampdiff(month, last_order_date, curdate()) as recency, # recency KPI
tot_orders, tot_sales, tot_quantity, tot_products, lifespan_months,
case when tot_orders = 0 then 0 # to avoid getting error because we are deviding
else
round(tot_sales / tot_orders , 2) end as avg_order_value, # average order value KPI
case when lifespan_months = 0 then tot_sales
else round(tot_sales / lifespan_months,2) end as avg_monthly_spends # monthly spends KPI
from customer_aggregation
;
















