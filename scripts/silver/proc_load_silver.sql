use silver;
/*
===============================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)  -- MySQL version
===============================================================================
Script Purpose:
    ETL process to populate the 'silver' database tables from the 'bronze' database.
    Actions performed:
        - Truncates Silver tables.
        - Inserts transformed and cleansed data from Bronze into Silver tables.

Parameters:
    None.

Usage Example:
    CALL silver.load_silver();

Notes:
    - Requires MySQL 8+ (CTEs, window functions, REGEXP, etc.).
    - TRUNCATE causes an implicit commit in MySQL, so there is no rollback
      of earlier tables if a later step fails.
    - PRINT in T-SQL is replaced by SELECT, which returns one result set per message.
===============================================================================
*/

DROP PROCEDURE IF EXISTS silver.load_silver;

DELIMITER //

CREATE PROCEDURE silver.load_silver()
BEGIN
    -- Variables must be declared before handlers
    DECLARE v_start_time       DATETIME;
    DECLARE v_end_time         DATETIME;
    DECLARE v_batch_start_time DATETIME;
    DECLARE v_batch_end_time   DATETIME;

    -- Equivalent of BEGIN CATCH
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg   = MESSAGE_TEXT,
            @err_no    = MYSQL_ERRNO,
            @err_state = RETURNED_SQLSTATE;
        SELECT '==========================================' AS log_message
        UNION ALL SELECT 'ERROR OCCURRED DURING LOADING SILVER LAYER'
        UNION ALL SELECT CONCAT('Error Message: ', @err_msg)
        UNION ALL SELECT CONCAT('Error Number: ', @err_no)
        UNION ALL SELECT CONCAT('Error State: ', @err_state)
        UNION ALL SELECT '==========================================';
    END;

    SET v_batch_start_time = NOW();
    SELECT '================================================' AS log_message
    UNION ALL SELECT 'Loading Silver Layer'
    UNION ALL SELECT '================================================'
    UNION ALL SELECT 'Loading CRM Tables'
    UNION ALL SELECT '------------------------------------------------';

    -- =========================================================================
    -- silver.crm_cust_info
    -- =========================================================================
    SET v_start_time = NOW();
    SELECT '>> Truncating Table: silver.crm_cust_info' AS log_message;
    TRUNCATE TABLE silver.crm_cust_info;
    SELECT '>> Inserting Data Into: silver.crm_cust_info' AS log_message;

    INSERT INTO silver.crm_cust_info (
        cst_id,
        cst_key,
        cst_firstname,
        cst_lastname,
        cst_marital_status,
        cst_gndr,
        cst_create_date
    )
    SELECT
        cst_id,
        cst_key,
        TRIM(cst_firstname) AS cst_firstname,
        TRIM(cst_lastname)  AS cst_lastname,
        CASE
            WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
            WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
            ELSE 'n/a'
        END AS cst_marital_status,
        CASE
            WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
            WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
            ELSE 'n/a'
        END AS cst_gndr,
        cst_create_date
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY cst_id
                ORDER BY cst_create_date DESC
            ) AS flag_last
        FROM bronze.crm_cust_info
        WHERE cst_id IS NOT NULL
          AND cst_id <> 0
    ) AS t
    WHERE flag_last = 1;   -- most recent record per customer

    SET v_end_time = NOW();
    SELECT CONCAT('>> Load Duration: ', TIMESTAMPDIFF(SECOND, v_start_time, v_end_time), ' seconds') AS log_message
    UNION ALL SELECT '>> -------------';

    -- =========================================================================
    -- silver.crm_prd_info
    -- =========================================================================
    SET v_start_time = NOW();
    SELECT '>> Truncating Table: silver.crm_prd_info' AS log_message;
    TRUNCATE TABLE silver.crm_prd_info;
    SELECT '>> Inserting Data Into: silver.crm_prd_info' AS log_message;

    INSERT INTO silver.crm_prd_info (
        prd_id,
        cat_id,
        prd_key,
        prd_nm,
        prd_cost,
        prd_line,
        prd_start_dt,
        prd_end_dt
    )
    SELECT
        prd_id,
        REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id,
        SUBSTRING(prd_key, 7, LENGTH(prd_key))      AS prd_key,
        prd_nm,
        IFNULL(prd_cost, 0)                         AS prd_cost,
        CASE
            WHEN UPPER(TRIM(prd_line)) = 'M' THEN 'Mountain'
            WHEN UPPER(TRIM(prd_line)) = 'R' THEN 'Road'
            WHEN UPPER(TRIM(prd_line)) = 'S' THEN 'Other Sales'
            WHEN UPPER(TRIM(prd_line)) = 'T' THEN 'Touring'
            ELSE 'n/a'
        END                                         AS prd_line,
        CAST(prd_start_dt AS DATE)                  AS prd_start_dt,
        DATE_SUB(
            CAST(
                LEAD(prd_start_dt) OVER (
                    PARTITION BY prd_key
                    ORDER BY prd_start_dt
                ) AS DATE
            ),
            INTERVAL 1 DAY
        )                                           AS prd_end_dt  -- one day before next start date
    FROM bronze.crm_prd_info;

    SET v_end_time = NOW();
    SELECT CONCAT('>> Load Duration: ', TIMESTAMPDIFF(SECOND, v_start_time, v_end_time), ' seconds') AS log_message
    UNION ALL SELECT '>> -------------';

    -- =========================================================================
    -- silver.crm_sales_details
    -- =========================================================================
    SET v_start_time = NOW();
    SELECT '>> Truncating Table: silver.crm_sales_details' AS log_message;
    TRUNCATE TABLE silver.crm_sales_details;
    SELECT '>> Inserting Data Into: silver.crm_sales_details' AS log_message;

    INSERT INTO silver.crm_sales_details (
        sls_ord_num,
        sls_prd_key,
        sls_cust_id,
        sls_order_dt,
        sls_ship_dt,
        sls_due_dt,
        sls_sales,
        sls_quantity,
        sls_price
    )
    WITH base AS (
        SELECT
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,
            CASE WHEN sls_order_dt = 0 OR LENGTH(sls_order_dt) != 8 THEN NULL
                 ELSE CAST(CAST(sls_order_dt AS CHAR) AS DATE) END AS sls_order_dt,
            CASE WHEN sls_ship_dt = 0 OR LENGTH(sls_ship_dt) != 8 THEN NULL
                 ELSE CAST(CAST(sls_ship_dt AS CHAR) AS DATE) END AS sls_ship_dt,
            CASE WHEN sls_due_dt = 0 OR LENGTH(sls_due_dt) != 8 THEN NULL
                 ELSE CAST(CAST(sls_due_dt AS CHAR) AS DATE) END AS sls_due_dt,
            sls_sales,
            sls_quantity,
            -- Step 1: repair price first
            CASE
                WHEN sls_price IS NULL OR sls_price <= 0
                THEN ABS(sls_sales) / NULLIF(sls_quantity, 0)
                ELSE sls_price
            END AS new_price
        FROM bronze.crm_sales_details
    )
    SELECT
        sls_ord_num,
        sls_prd_key,
        sls_cust_id,
        sls_order_dt,
        sls_ship_dt,
        sls_due_dt,
        -- Step 2: repair sales using the repaired price
        CASE
            WHEN sls_sales IS NULL
                 OR sls_sales <= 0
                 OR sls_sales != sls_quantity * new_price
            THEN sls_quantity * new_price
            ELSE sls_sales
        END AS sls_sales,
        sls_quantity,
        new_price AS sls_price
    FROM base;

    SET v_end_time = NOW();
    SELECT CONCAT('>> Load Duration: ', TIMESTAMPDIFF(SECOND, v_start_time, v_end_time), ' seconds') AS log_message
    UNION ALL SELECT '>> -------------';

    SELECT '------------------------------------------------' AS log_message
    UNION ALL SELECT 'Loading ERP Tables'
    UNION ALL SELECT '------------------------------------------------';

    -- =========================================================================
    -- silver.erp_cust_az12
    -- =========================================================================
    SET v_start_time = NOW();
    SELECT '>> Truncating Table: silver.erp_cust_az12' AS log_message;
    TRUNCATE TABLE silver.erp_cust_az12;
    SELECT '>> Inserting Data Into: silver.erp_cust_az12' AS log_message;

    INSERT INTO silver.erp_cust_az12 (cid, bdate, gen)
    WITH cleaned AS (
        SELECT
            cid,
            bdate,
            UPPER(TRIM(
                REPLACE(
                REPLACE(
                REPLACE(
                REPLACE(gen, CHAR(13), ''),
                             CHAR(10), ''),
                             CHAR(9),  ''),
                             CONVERT(UNHEX('C2A0') USING utf8mb4), '')
            )) AS g
        FROM bronze.erp_cust_az12
    )
    SELECT
        CASE
            WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LENGTH(cid))  -- remove 'NAS' prefix
            ELSE cid
        END AS cid,
        CASE
            WHEN bdate > CURRENT_DATE() THEN NULL                      -- future birthdates -> NULL
            ELSE bdate
        END AS bdate,
        CASE
            WHEN g IN ('F', 'FEMALE') THEN 'Female'
            WHEN g IN ('M', 'MALE')   THEN 'Male'
            ELSE 'n/a'
        END AS gen
    FROM cleaned;

    SET v_end_time = NOW();
    SELECT CONCAT('>> Load Duration: ', TIMESTAMPDIFF(SECOND, v_start_time, v_end_time), ' seconds') AS log_message
    UNION ALL SELECT '>> -------------';

    -- =========================================================================
    -- silver.erp_loc_a101
    -- =========================================================================
    SET v_start_time = NOW();
    SELECT '>> Truncating Table: silver.erp_loc_a101' AS log_message;
    TRUNCATE TABLE silver.erp_loc_a101;
    SELECT '>> Inserting Data Into: silver.erp_loc_a101' AS log_message;

    INSERT INTO silver.erp_loc_a101 (cid, cntry)
    WITH cleaned AS (
        SELECT
            REPLACE(cid, '-', '') AS cid,
            TRIM(
                REPLACE(
                REPLACE(
                REPLACE(
                REPLACE(cntry, CHAR(13), ''),
                               CHAR(10), ''),
                               CHAR(9),  ''),
                               CONVERT(UNHEX('C2A0') USING utf8mb4), '')
            ) AS c
        FROM bronze.erp_loc_a101
    )
    SELECT
        cid,
        CASE
            WHEN c = 'DE'            THEN 'Germany'
            WHEN c IN ('US', 'USA')  THEN 'United States'
            WHEN c = '' OR c IS NULL THEN 'n/a'
            ELSE c
        END AS cntry
    FROM cleaned;

    SET v_end_time = NOW();
    SELECT CONCAT('>> Load Duration: ', TIMESTAMPDIFF(SECOND, v_start_time, v_end_time), ' seconds') AS log_message
    UNION ALL SELECT '>> -------------';

    -- =========================================================================
    -- silver.erp_px_cat_g1v2
    -- =========================================================================
    SET v_start_time = NOW();
    SELECT '>> Truncating Table: silver.erp_px_cat_g1v2' AS log_message;
    TRUNCATE TABLE silver.erp_px_cat_g1v2;
    SELECT '>> Inserting Data Into: silver.erp_px_cat_g1v2' AS log_message;

    INSERT INTO silver.erp_px_cat_g1v2 (id, cat, subcat, maintenance)
    SELECT
        id,
        cat,
        subcat,
        TRIM(
            REPLACE(
            REPLACE(
            REPLACE(
            REPLACE(maintenance, CHAR(13), ''),
                                 CHAR(10), ''),
                                 CHAR(9),  ''),
                                 CONVERT(UNHEX('C2A0') USING utf8mb4), '')
        ) AS maintenance   -- strip hidden \r etc. from the last CSV column
    FROM bronze.erp_px_cat_g1v2;

    SET v_end_time = NOW();
    SELECT CONCAT('>> Load Duration: ', TIMESTAMPDIFF(SECOND, v_start_time, v_end_time), ' seconds') AS log_message
    UNION ALL SELECT '>> -------------';

    -- =========================================================================
    SET v_batch_end_time = NOW();
    SELECT '==========================================' AS log_message
    UNION ALL SELECT 'Loading Silver Layer is Completed'
    UNION ALL SELECT CONCAT('   - Total Load Duration: ',
                            TIMESTAMPDIFF(SECOND, v_batch_start_time, v_batch_end_time), ' seconds')
    UNION ALL SELECT '==========================================';
END //

DELIMITER ;

-- Run it:
-- CALL silver.load_silver();
 
