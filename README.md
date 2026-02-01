# SQL E-Commerce Sales Analysis
End-to-end SQL analysis transforming raw transactional data into actionable customer and product insights across 7 countries and 4 product categories.

## Executive Summary
This SQL project consolidates 60K+ transactional records spanning 2010–2014 to deliver deep-dive customer segmentation, product performance benchmarking, and revenue trend analysis — all built using window functions, CTEs, and time-series aggregation.

**Key outcomes:**

- Identified that **8.9% of customers (VIP segment) drive 36.7% of total revenue ($10.76M)**, enabling targeted retention strategies
- Revealed a **96.5% revenue concentration in Bikes** ($28.3M), exposing category diversification risk across Accessories and Clothing
- Built a **three-tier customer segmentation model** (VIP / Regular / New) based on lifespan and spending thresholds, replacing ad-hoc customer reporting
- Produced two reusable reporting views (`report_customers`, `report_products`) consolidating 14+ KPIs per entity for downstream dashboarding


## Business Context and Objectives

**The Challenge:**
Sales operations teams relied on disconnected flat files to monitor customer health and product performance, making cross-dimensional analysis time-consuming and segment-level insights invisible. Stakeholders needed structured, query-ready outputs that could surface behavioral patterns and revenue concentration risks.

**Project Scope:**
This SQL solution processes 60,398 sales transactions across 18,484 customers and 295 products, enabling:

- Customer lifetime and spending segmentation (VIP, Regular, New)
- Product performance benchmarking with cost-segment and revenue-segment classification
- Multi-dimensional trend analysis (yearly, monthly, rolling totals)
- Category and product contribution analysis with percentage breakdowns
- Year-over-year product performance comparison with average benchmarking
  

## Data Architecture

### Data Structure

| Table | Role | Records | Key Fields |
|---|---|---|---|
| `gold_fact_sales` | Fact table | 60,398 | order_number, product_key, customer_key, order_date, sales_amount, quantity |
| `gold_dim_customers` | Customer dimension | 18,484 | customer_key, first_name, last_name, country, gender, birthdate |
| `gold_dim_products` | Product dimension | 295 | product_key, product_name, category, subcategory, cost |
| `gold_report_customers` | Customer report view | 18,482 | Aggregated KPIs: total_sales, total_orders, lifespan, avg_order_value, segment |
| `gold_report_products` | Product report view | 130 | Aggregated KPIs: total_sales, total_customers, avg_selling_price, segment |

### Data Model
Star schema with `gold_fact_sales` as the central fact table, joined to `gold_dim_customers` and `gold_dim_products` via foreign keys (`customer_key`, `product_key`). The two report views are derived outputs — fully aggregated, segment-labeled summaries built on top of the star schema through multi-step CTEs.


## Technical Implementation

### Query Architecture

The project is organized into four analytical layers, each progressively more complex:

**Layer 1 — Exploratory & Trend Analysis:** Basic aggregations to validate data and establish baseline metrics (daily totals, yearly breakdowns, monthly patterns).

**Layer 2 — Time-Series & Running Totals:** Window functions (`SUM() OVER`) to compute cumulative revenue across months, with `PARTITION BY` to reset running totals at year boundaries — enabling clean YoY visual comparisons.

**Layer 3 — Comparative Benchmarking:** Product-level year-over-year analysis using `LAG()` for prior-year values and per-product `AVG() OVER` for average benchmarking. Flags each year as `above avg`, `below avg`, or `avg` for rapid scanning.

**Layer 4 — Segmentation & Reporting Views:** Full CTE pipelines that join fact and dimension tables, compute derived KPIs (recency, lifespan, avg order value, avg monthly spend), and classify entities into business segments using threshold-based `CASE` logic.

### Key SQL Patterns

**Running total with annual reset:**
```sql
SELECT 
    order_year,
    order_month,
    tot_sales,
    SUM(tot_sales) OVER (PARTITION BY order_year ORDER BY order_month) AS running_tot_sales
FROM (
    SELECT 
        YEAR(order_date) AS order_year,
        CAST(DATE_FORMAT(order_date, '%Y-%m-01') AS DATE) AS order_month,
        SUM(sales_amount) AS tot_sales
    FROM gold_sales
    WHERE order_date IS NOT NULL AND order_date <> ''
    GROUP BY YEAR(order_date), CAST(DATE_FORMAT(order_date, '%Y-%m-01') AS DATE)
) t
ORDER BY order_year, order_month;
```

**Year-over-year product benchmarking:**
```sql
WITH yearly_product_sales AS (
    SELECT 
        YEAR(s.order_date) AS order_year,
        p.product_name,
        SUM(s.sales_amount) AS tot_sales
    FROM gold_sales s
    LEFT JOIN gold_products p ON s.product_key = p.product_key
    WHERE s.order_date IS NOT NULL AND s.order_date <> ''
    GROUP BY YEAR(s.order_date), p.product_name
)
SELECT *,
    AVG(tot_sales) OVER (PARTITION BY product_name) AS avg_sales,
    tot_sales - AVG(tot_sales) OVER (PARTITION BY product_name) AS diff_avg,
    CASE
        WHEN tot_sales < AVG(tot_sales) OVER (PARTITION BY product_name) THEN 'below avg'
        WHEN tot_sales > AVG(tot_sales) OVER (PARTITION BY product_name) THEN 'above avg'
        ELSE 'avg'
    END AS performance_flag,
    LAG(tot_sales) OVER (PARTITION BY product_name ORDER BY order_year) AS prev_year_sales,
    tot_sales - LAG(tot_sales) OVER (PARTITION BY product_name ORDER BY order_year) AS diff_prev
FROM yearly_product_sales
ORDER BY product_name, order_year;
```

**Three-tier customer segmentation:**
```sql
WITH customer_spending AS (
    SELECT 
        c.customer_key,
        SUM(s.sales_amount) AS tot_sales,
        TIMESTAMPDIFF(MONTH, MIN(order_date), MAX(order_date)) AS lifespan_months
    FROM gold_sales s
    LEFT JOIN gold_customers c ON s.customer_key = c.customer_key
    GROUP BY customer_key
)
SELECT 
    CASE
        WHEN lifespan_months >= 12 AND tot_sales > 5000 THEN 'VIP'
        WHEN lifespan_months >= 12 AND tot_sales < 5000 THEN 'Regular'
        ELSE 'New'
    END AS segment,
    COUNT(DISTINCT customer_key) AS num_customers
FROM customer_spending
GROUP BY segment;
```


## Key Findings & Insights

### Finding 1: Revenue is Heavily Concentrated in Bikes

| Category | Revenue | Share |
|---|---|---|
| Bikes | $28.32M | 96.5% |
| Accessories | $700K | 2.4% |
| Clothing | $340K | 1.2% |

Bikes drive nearly all revenue across Mountain, Road, and Touring lines. Accessories and Clothing contribute under 4% combined. **Business Impact:** Any disruption to Bike supply, pricing, or demand directly threatens the entire revenue base. A category diversification strategy — scaling Accessories and Clothing — would reduce concentration risk and create secondary growth engines.

### Finding 2: A Small VIP Segment Drives Disproportionate Revenue

| Segment | Customers | Revenue | Share | Avg Spend/Customer |
|---|---|---|---|---|
| VIP | 1,653 (8.9%) | $10.76M | 36.7% | $6,510 |
| Regular | 2,200 (11.9%) | $7.50M | 25.6% | $3,411 |
| New | 14,629 (79.1%) | $11.09M | 37.8% | $758 |

VIP customers (lifespan ≥ 12 months, total spend > $5,000) spend **8.6× more per customer than New customers** while representing under 9% of the base. Regular customers sit in the middle — long-tenured but spending below the VIP threshold. **Business Impact:** Retention investment should concentrate on VIP customers. Regular customers represent the highest-potential conversion opportunity — targeted spend-increase campaigns could shift a meaningful share into VIP status.

### Finding 3: Product Revenue Follows an 80/20 Pattern

| Segment | Products | Revenue | Share |
|---|---|---|---|
| High-Performer | 66 (50.8%) | $27.64M | 94.2% |
| Mid-Range | 58 (44.6%) | $1.67M | 5.7% |
| Low-Performer | 6 (4.6%) | $35.7K | 0.1% |

66 High-Performer products generate 94.2% of all product revenue. The 6 Low-Performers contribute less than $36K combined. **Business Impact:** Portfolio rationalization should target Low-Performers for discontinuation or redesign. Mid-Range products warrant investigation — understanding whether they are pricing, positioning, or demand issues would clarify whether to invest or exit.

### Finding 4: Geographic Revenue is Dominated by Two Markets

United States (31.2%, $9.16M) and Australia (30.9%, $9.06M) together account for over 62% of total sales. The remaining five markets — UK, Germany, France, Canada — each contribute between 6.7% and 11.6%. **Business Impact:** Growth strategy should balance deepening share in the two dominant markets against developing the mid-tier markets (UK, Germany, France) where there is likely untapped demand given their established customer bases.

### Finding 5: Clear Seasonality with a Strong H2 Peak

Monthly revenue across all years shows a consistent seasonal curve: sales ramp from a Q1 trough (~$1.7–1.9M/month) through a mid-year inflection, peaking in Q4 — with December delivering the highest monthly total ($3.21M) and November close behind ($2.98M). **Business Impact:** Inventory, staffing, and marketing budgets should be front-loaded into Q3–Q4. The Q1 dip presents an opportunity to test promotional strategies that could smooth demand and improve annual revenue distribution.


## Recommendations & Business Impact

**1. Protect and Diversify the Revenue Base (Bikes Concentration Risk)**
Bikes represent 96.5% of revenue — any market shift in this category is existential. Develop a 12-month scaling plan for Accessories and Clothing, starting with the highest-margin subcategories. Target: bring non-Bike revenue from 3.5% to 8–10% within two years.

**2. Build a VIP Retention Program**
1,653 VIP customers generate $10.76M. Model the revenue impact of even a 5% VIP churn rate (~$538K annual loss). Implement quarterly engagement touchpoints and early-access incentives for this segment. Simultaneously, design a Regular-to-VIP conversion campaign — the 2,200 Regular customers already have the behavioral profile (long tenure); they need a spending nudge.

**3. Rationalize the Product Portfolio**
The 6 Low-Performer products contribute $35.7K — less than 0.2% of revenue. Discontinue or consolidate these SKUs to reduce operational complexity. Conduct a deeper margin analysis on Mid-Range products before committing to exit decisions.

**4. Invest in H2 and Develop Q1 Demand Strategies**
Align marketing spend and inventory builds with the Q3–Q4 seasonal peak. For Q1, test targeted promotions or loyalty-reward activations with the VIP and Regular segments to test whether off-peak demand can be stimulated without margin erosion.


## Future Enhancements

**1. Margin & Profitability Analysis**
Integrate cost data from `gold_dim_products` into the sales fact to compute per-transaction gross margin. Build a product-level P&L view to shift the conversation from revenue to profit contribution.

**2. Cohort Analysis**
Segment customers by acquisition month and track retention and revenue decay over time. This would reveal whether newer cohorts behave differently from historical ones — critical for evaluating marketing effectiveness.

**3. Geographic Expansion Modeling**
Layer country-level customer density and average order value to identify which mid-tier markets (UK, Germany, France) have the strongest expansion potential relative to current investment.

**4. Predictive Churn Scoring**
Use the `recency` and `lifespan` KPIs already computed in `report_customers` as input features for a simple churn model — flagging at-risk VIP customers before they lapse.
