# Technical Documentation: MySQL Data Warehouse

This document describes how the warehouse works in detail: data lineage, the Silver ETL procedure, transformation rules, the Gold data catalog, naming conventions, data quality checks and troubleshooting. For a project overview and quick start, see `README.md`.

---

## 1. Data Lineage

| Gold object | Silver source(s) | Bronze source(s) |
|-------------|------------------|------------------|
| `gold.dim_customers` | `silver.crm_cust_info`, `silver.erp_cust_az12`, `silver.erp_loc_a101` | `bronze.crm_cust_info`, `bronze.erp_cust_az12`, `bronze.erp_loc_a101` |
| `gold.dim_products` | `silver.crm_prd_info`, `silver.erp_px_cat_g1v2` | `bronze.crm_prd_info`, `bronze.erp_px_cat_g1v2` |
| `gold.fact_sales` | `silver.crm_sales_details`, `gold.dim_products`, `gold.dim_customers` | `bronze.crm_sales_details` |

### Join keys between systems

| Relationship | Join condition | Key preparation |
|--------------|----------------|-----------------|
| CRM customer to ERP birthdate/gender | `crm_cust_info.cst_key = erp_cust_az12.cid` | `NAS` prefix removed from ERP `cid` |
| CRM customer to ERP country | `crm_cust_info.cst_key = erp_loc_a101.cid` | `-` removed from ERP `cid` |
| CRM product to ERP category | `crm_prd_info.cat_id = erp_px_cat_g1v2.id` | `cat_id` derived from first 5 characters of `prd_key`, `-` replaced with `_` |
| Sales to product | `crm_sales_details.sls_prd_key = dim_products.product_number` | `prd_key` is the part of the original key after character 6 |
| Sales to customer | `crm_sales_details.sls_cust_id = dim_customers.customer_id` | None |

---

## 2. Silver ETL Procedure

**Object:** `silver.load_silver()`
**File:** `scripts/silver/load_silver_mysql.sql`
**Run:** `CALL silver.load_silver();`
**Parameters:** none. **Returns:** log messages as result sets.

### Execution order

1. `silver.crm_cust_info`
2. `silver.crm_prd_info`
3. `silver.crm_sales_details`
4. `silver.erp_cust_az12`
5. `silver.erp_loc_a101`
6. `silver.erp_px_cat_g1v2`

Each step follows the same pattern: record the start time, truncate the table, insert the transformed rows from Bronze, then record the duration.

### Error handling

A `DECLARE EXIT HANDLER FOR SQLEXCEPTION` captures the message, MySQL error number and SQLSTATE using `GET DIAGNOSTICS`, returns them as a result set, and stops the procedure.

### Behaviour to be aware of

- **Full refresh:** every run truncates and reloads all Silver tables.
- **Implicit commit:** `TRUNCATE` commits immediately in MySQL. If a step fails, tables loaded before it remain loaded and the failed table may be empty.
- **Idempotent:** running the procedure twice gives the same result, as long as Bronze has not changed.

---

## 3. Transformation Rules by Table

### 3.1 `silver.crm_cust_info`

| Column | Rule |
|--------|------|
| `cst_id` | Rows with NULL or 0 are removed |
| `cst_key` | Passed through |
| `cst_firstname`, `cst_lastname` | `TRIM` |
| `cst_marital_status` | `S` → Single, `M` → Married, anything else → `n/a` (case-insensitive, trimmed) |
| `cst_gndr` | `F` → Female, `M` → Male, anything else → `n/a` (case-insensitive, trimmed) |
| `cst_create_date` | Passed through |
| Deduplication | One row per `cst_id`: the latest by `cst_create_date` (`ROW_NUMBER() ... ORDER BY cst_create_date DESC`) |

### 3.2 `silver.crm_prd_info`

| Column | Rule |
|--------|------|
| `cat_id` | `REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_')` |
| `prd_key` | `SUBSTRING(prd_key, 7, LENGTH(prd_key))` |
| `prd_cost` | NULL → 0 |
| `prd_line` | `M` → Mountain, `R` → Road, `S` → Other Sales, `T` → Touring, else `n/a` |
| `prd_start_dt` | Cast to `DATE` |
| `prd_end_dt` | One day before the next `prd_start_dt` for the same product (`LEAD` partitioned by `prd_key`, ordered by `prd_start_dt`). The current version of a product has a NULL end date |

### 3.3 `silver.crm_sales_details`

| Column | Rule |
|--------|------|
| `sls_order_dt`, `sls_ship_dt`, `sls_due_dt` | Source is an integer in `yyyymmdd` form. Value 0 or length other than 8 → NULL, otherwise converted to `DATE` |
| `sls_price` | If NULL or ≤ 0: `ABS(sls_sales) / NULLIF(sls_quantity, 0)`. Otherwise unchanged |
| `sls_sales` | If NULL, ≤ 0 or different from `sls_quantity × sls_price`: recalculated as `sls_quantity × sls_price`, using the **repaired** price. Otherwise unchanged |
| `sls_quantity` | Passed through |

The price repair runs in a CTE first, because a `SELECT` cannot reuse an alias defined in the same select list.

**Decision table**

| Original sales | Original price | Result |
|----------------|----------------|--------|
| Valid | Valid, and sales = qty × price | Unchanged |
| Valid | Valid, but sales ≠ qty × price | Sales recalculated from price |
| Valid | 0, NULL or negative | Price derived from sales, then sales re-checked |
| 0, NULL or negative | Valid | Sales = qty × price |
| 0, NULL or negative | 0, NULL or negative | Not recoverable: result is 0 or NULL |

### 3.4 `silver.erp_cust_az12`

| Column | Rule |
|--------|------|
| `cid` | If it starts with `NAS`, the first 3 characters are removed |
| `bdate` | Dates later than today → NULL |
| `gen` | Hidden characters removed, then `F` / `FEMALE` → Female, `M` / `MALE` → Male, else `n/a` |

### 3.5 `silver.erp_loc_a101`

| Column | Rule |
|--------|------|
| `cid` | `-` removed |
| `cntry` | Hidden characters removed and trimmed. `DE` → Germany, `US` / `USA` → United States, empty or NULL → `n/a`, otherwise unchanged |

### 3.6 `silver.erp_px_cat_g1v2`

| Column | Rule |
|--------|------|
| `id`, `cat`, `subcat` | Passed through |
| `maintenance` | Hidden characters removed and trimmed (expected values: `Yes`, `No`) |

### 3.7 Hidden character cleanup (reusable pattern)

CSV files created on Windows end each line with `\r\n`. When loaded, the `\r` stays attached to the last column. MySQL's `TRIM()` removes only spaces, so `'F\r'` does not equal `'F'`.

```sql
TRIM(
  REPLACE(REPLACE(REPLACE(REPLACE(col, CHAR(13), ''),    -- carriage return
                                       CHAR(10), ''),    -- line feed
                                       CHAR(9),  ''),    -- tab
                                       CONVERT(UNHEX('C2A0') USING utf8mb4), '')  -- non-breaking space
)
```

`CHAR(160)` must not be used: it returns a binary string and fails with error 3854 on UTF-8 columns.

A simpler alternative for most cases is `REGEXP_REPLACE(col, '[[:space:]]', '')`.

---

## 4. Gold Data Catalog

> Data types below describe the intended meaning. Check them against your actual table definitions.

### 4.1 `gold.dim_customers`

**Purpose:** one row per customer, combining CRM and ERP attributes.
**Grain:** one row per `customer_id`.

| Column | Type | Description |
|--------|------|-------------|
| `customer_key` | INT | Surrogate key, `ROW_NUMBER() OVER (ORDER BY cst_id)` |
| `customer_id` | INT | Customer ID from CRM |
| `customer_number` | VARCHAR | Alphanumeric customer key, used to join ERP data |
| `first_name` | VARCHAR | Customer first name, trimmed |
| `last_name` | VARCHAR | Customer last name, trimmed |
| `country` | VARCHAR | Country name, `n/a` if unknown |
| `marital_status` | VARCHAR | `Single`, `Married` or `n/a` |
| `gender` | VARCHAR | `Male`, `Female` or `n/a`. CRM value is used when available, otherwise the ERP value |
| `birthdate` | DATE | Birth date, NULL if missing or in the future |
| `create_date` | DATE | Date the customer record was created in CRM |

### 4.2 `gold.dim_products`

**Purpose:** one row per current product with category information.
**Grain:** one row per product (historical versions excluded by `prd_end_dt IS NULL`).

| Column | Type | Description |
|--------|------|-------------|
| `product_key` | INT | Surrogate key, `ROW_NUMBER() OVER (ORDER BY prd_start_dt, prd_key)` |
| `product_id` | INT | Product ID from CRM |
| `product_number` | VARCHAR | Product key, used to join sales |
| `product_name` | VARCHAR | Product name |
| `category_id` | VARCHAR | Category code derived from the product key |
| `category` | VARCHAR | Product category (ERP) |
| `subcategory` | VARCHAR | Product subcategory (ERP) |
| `maintenance` | VARCHAR | Whether the product requires maintenance: `Yes` or `No` |
| `cost` | DECIMAL | Product cost, 0 if missing |
| `product_line` | VARCHAR | `Mountain`, `Road`, `Other Sales`, `Touring` or `n/a` |
| `start_date` | DATE | Date the current version became active |

### 4.3 `gold.fact_sales`

**Purpose:** sales transactions linked to the dimensions.
**Grain:** one row per order line from `crm_sales_details`.

| Column | Type | Description |
|--------|------|-------------|
| `order_number` | VARCHAR | Sales order number |
| `product_key` | INT | Foreign key to `dim_products.product_key` |
| `customer_key` | INT | Foreign key to `dim_customers.customer_key` |
| `order_date` | DATE | Date the order was placed |
| `shipping_date` | DATE | Date the order was shipped |
| `due_date` | DATE | Date payment was due |
| `sales_amount` | DECIMAL | Line total, equal to `quantity × price` |
| `quantity` | INT | Units ordered |
| `price` | DECIMAL | Price per unit |

Rows are joined with `LEFT JOIN`, so a sale with an unmatched product or customer keeps its row with a NULL key.

---

## 5. Naming Conventions

| Item | Convention |
|------|------------|
| Schemas | `bronze`, `silver`, `gold` |
| Bronze and Silver tables | `<source>_<entity>`, same name as the source file (for example `crm_cust_info`, `erp_loc_a101`) |
| Gold objects | `dim_<entity>` for dimensions, `fact_<entity>` for facts, always business-friendly names |
| Surrogate keys | `<entity>_key` |
| Stored procedures | `load_<layer>` (for example `silver.load_silver`) |
| Script files | `ddl_<layer>.sql`, `load_<layer>_mysql.sql`, `create_<layer>_views_mysql.sql` |
| Missing text values | `n/a` |
| Gold column names | Descriptive snake_case (`first_name`, `order_date`), not source-system abbreviations |

---

## 6. Data Quality Checks

Run these after every load.

| # | Check | Query | Expected |
|---|-------|-------|----------|
| 1 | No duplicate customers | `SELECT cst_id, COUNT(*) FROM silver.crm_cust_info GROUP BY cst_id HAVING COUNT(*) > 1;` | 0 rows |
| 2 | No unwanted spaces | `SELECT cst_firstname FROM silver.crm_cust_info WHERE cst_firstname != TRIM(cst_firstname);` | 0 rows |
| 3 | Standardised gender | `SELECT DISTINCT gen FROM silver.erp_cust_az12;` | Female, Male, n/a |
| 4 | Standardised country | `SELECT DISTINCT cntry FROM silver.erp_loc_a101;` | Full names and n/a only |
| 5 | Standardised maintenance | `SELECT DISTINCT maintenance FROM silver.erp_px_cat_g1v2;` | Yes, No |
| 6 | Product dates in order | `SELECT * FROM silver.crm_prd_info WHERE prd_end_dt < prd_start_dt;` | 0 rows |
| 7 | Sales consistency | `SELECT * FROM silver.crm_sales_details WHERE sls_sales != sls_quantity * sls_price;` | 0 rows |
| 8 | Order date before ship and due dates | `SELECT * FROM silver.crm_sales_details WHERE sls_order_dt > sls_ship_dt OR sls_order_dt > sls_due_dt;` | 0 rows |
| 9 | Fact to dimension integrity | `SELECT * FROM gold.fact_sales WHERE product_key IS NULL OR customer_key IS NULL;` | 0 rows |
| 10 | ERP to CRM key match | `SELECT cid FROM silver.erp_loc_a101 WHERE cid NOT IN (SELECT cst_key FROM silver.crm_cust_info);` | 0 rows |
| 11 | No hidden characters | `SELECT DISTINCT HEX(maintenance) FROM silver.erp_px_cat_g1v2;` | `596573` (Yes), `4E6F` (No) |

---

## 7. Troubleshooting

| Symptom | Likely cause | Resolution |
|---------|--------------|------------|
| `CASE` returns `n/a` for values that look correct | Hidden `\r` in the last CSV column | Use the cleanup pattern in section 3.7. Confirm with `HEX(col)` |
| `Error 3854: Cannot convert string '\xA0' from binary to utf8mb3` | `CHAR(160)` returns binary | Use `CONVERT(UNHEX('C2A0') USING utf8mb4)` |
| `DISTINCT` shows `Yes` twice | One value has an invisible trailing character | Clean the column, then re-check |
| Sales and price disagree after the load | Price repair and sales repair were done in the same `SELECT` | Repair price in a CTE first, then sales (section 3.3) |
| `fact_sales` has NULL `customer_key` or `product_key` | Key mismatch between systems | Check `NAS` prefix, `-` in IDs, and hidden characters in `cid` |
| `dim_customers` has many NULL `country` or `birthdate` | ERP `cid` does not match `cst_key` | Compare `cst_key` and `cid` with `HEX()` |
| Procedure fails with a syntax error in Workbench | `DELIMITER` not set | Keep `DELIMITER //` before and `DELIMITER ;` after the procedure |
| `INSERT ... WITH ... SELECT` errors | Older MySQL version | Upgrade to MySQL 8, or move the CTE into a subquery |
| Silver table is empty after a failed run | `TRUNCATE` ran before the failure | Fix the error and call the procedure again |

---

## 8. Change Log

| Version | Change |
|---------|--------|
| 1.0 | Initial Silver load procedure, Gold views and documentation, converted from the T-SQL original to MySQL |
| 1.1 | Added hidden character cleanup for `gen`, `cntry` and `maintenance` |
| 1.2 | Fixed sales and price repair order using a CTE |

---

## 9. Possible Future Improvements

- Add a load log table instead of `SELECT` messages.
- Move to incremental loads using `cst_create_date` or a batch ID.
- Wrap each table load in a transaction-aware design (for example, load into a staging table and swap).
- Materialise the Gold dimensions as tables to keep surrogate keys stable.
- Add automated data quality tests that run after `CALL silver.load_silver()`.
- Add a `date` dimension.
