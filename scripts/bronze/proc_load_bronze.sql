/*
===============================================================================
Script: Load Bronze Layer (Source -> Bronze)
===============================================================================
Script Purpose:
    This script loads data into the Bronze layer from external CSV files.

    It performs the following actions:
    - Truncates the Bronze tables before loading data.
    - Uses LOAD DATA LOCAL INFILE to import CSV files.
    - Calculates individual table loading duration.
    - Calculates total loading duration.
    - Displays the number of records loaded into each table.

Note:
    Update the CSV file paths according to your system.
===============================================================================
*/

USE bronze;

SET @batch_start_time = NOW();

SELECT '================================================' AS '';
SELECT 'Loading Bronze Layer' AS '';
SELECT '================================================' AS '';

SELECT '------------------------------------------------' AS '';
SELECT 'Loading CRM Tables' AS '';
SELECT '------------------------------------------------' AS '';

SET @start_time = NOW();

SELECT '>> Truncating Table: bronze.crm_cust_info' AS '';
TRUNCATE TABLE crm_cust_info;

SELECT '>> Inserting Data Into: bronze.crm_cust_info' AS '';

LOAD DATA LOCAL INFILE
'C:/Users/ASUS/Downloads/sql-data-warehouse-project (1)/sql-data-warehouse-project/01_datasets/source_crm/cust_info.csv'
INTO TABLE crm_cust_info
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SET @end_time = NOW();

SELECT CONCAT('>> Load Duration: ',
TIMESTAMPDIFF(SECOND, @start_time, @end_time),
' seconds') AS '';

SELECT '>> -------------' AS '';


SET @start_time = NOW();

SELECT '>> Truncating Table: bronze.crm_prd_info' AS '';
TRUNCATE TABLE crm_prd_info;

SELECT '>> Inserting Data Into: bronze.crm_prd_info' AS '';

LOAD DATA LOCAL INFILE
'C:/Users/ASUS/Downloads/sql-data-warehouse-project (1)/sql-data-warehouse-project/01_datasets/source_crm/prd_info.csv'
INTO TABLE crm_prd_info
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SET @end_time = NOW();

SELECT CONCAT('>> Load Duration: ',
TIMESTAMPDIFF(SECOND, @start_time, @end_time),
' seconds') AS '';

SELECT '>> -------------' AS '';


SET @start_time = NOW();

SELECT '>> Truncating Table: bronze.crm_sales_details' AS '';
TRUNCATE TABLE crm_sales_details;

SELECT '>> Inserting Data Into: bronze.crm_sales_details' AS '';

LOAD DATA LOCAL INFILE
'C:/Users/ASUS/Downloads/sql-data-warehouse-project (1)/sql-data-warehouse-project/01_datasets/source_crm/sales_details.csv'
INTO TABLE crm_sales_details
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SET @end_time = NOW();

SELECT CONCAT('>> Load Duration: ',
TIMESTAMPDIFF(SECOND, @start_time, @end_time),
' seconds') AS '';

SELECT '>> -------------' AS '';


SELECT '------------------------------------------------' AS '';
SELECT 'Loading ERP Tables' AS '';
SELECT '------------------------------------------------' AS '';


SET @start_time = NOW();

SELECT '>> Truncating Table: bronze.erp_loc_a101' AS '';
TRUNCATE TABLE erp_loc_a101;

SELECT '>> Inserting Data Into: bronze.erp_loc_a101' AS '';

LOAD DATA LOCAL INFILE
'C:/Users/ASUS/Downloads/sql-data-warehouse-project (1)/sql-data-warehouse-project/01_datasets/source_erp/loc_a101.csv'
INTO TABLE erp_loc_a101
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SET @end_time = NOW();

SELECT CONCAT('>> Load Duration: ',
TIMESTAMPDIFF(SECOND, @start_time, @end_time),
' seconds') AS '';

SELECT '>> -------------' AS '';


SET @start_time = NOW();

SELECT '>> Truncating Table: bronze.erp_cust_az12' AS '';
TRUNCATE TABLE erp_cust_az12;

SELECT '>> Inserting Data Into: bronze.erp_cust_az12' AS '';

LOAD DATA LOCAL INFILE
'C:/Users/ASUS/Downloads/sql-data-warehouse-project (1)/sql-data-warehouse-project/01_datasets/source_erp/cust_az12.csv'
INTO TABLE erp_cust_az12
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SET @end_time = NOW();

SELECT CONCAT('>> Load Duration: ',
TIMESTAMPDIFF(SECOND, @start_time, @end_time),
' seconds') AS '';

SELECT '>> -------------' AS '';


SET @start_time = NOW();

SELECT '>> Truncating Table: bronze.erp_px_cat_g1v2' AS '';
TRUNCATE TABLE erp_px_cat_g1v2;

SELECT '>> Inserting Data Into: bronze.erp_px_cat_g1v2' AS '';

LOAD DATA LOCAL INFILE
'C:/Users/ASUS/Downloads/sql-data-warehouse-project (1)/sql-data-warehouse-project/01_datasets/source_erp/px_cat_g1v2.csv'
INTO TABLE erp_px_cat_g1v2
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SET @end_time = NOW();

SELECT CONCAT('>> Load Duration: ',
TIMESTAMPDIFF(SECOND, @start_time, @end_time),
' seconds') AS '';

SELECT '>> -------------' AS '';


SET @batch_end_time = NOW();

SELECT '==========================================' AS '';
SELECT 'Loading Bronze Layer is Completed' AS '';

SELECT CONCAT(
'Total Load Duration: ',
TIMESTAMPDIFF(SECOND, @batch_start_time, @batch_end_time),
' seconds'
) AS '';

SELECT '==========================================' AS '';


SELECT '==========================================' AS '';
SELECT 'Bronze Layer Record Counts' AS '';
SELECT '==========================================' AS '';

SELECT COUNT(*) AS crm_cust_info_count FROM crm_cust_info;
SELECT COUNT(*) AS crm_prd_info_count FROM crm_prd_info;
SELECT COUNT(*) AS crm_sales_details_count FROM crm_sales_details;
SELECT COUNT(*) AS erp_loc_a101_count FROM erp_loc_a101;
SELECT COUNT(*) AS erp_cust_az12_count FROM erp_cust_az12;
SELECT COUNT(*) AS erp_px_cat_g1v2_count FROM erp_px_cat_g1v2;
