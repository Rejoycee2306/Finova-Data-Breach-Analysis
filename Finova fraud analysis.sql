CREATE DATABASE finova_db;
USE finova_db;
-- Quick validation checks 
SELECT COUNT(*) AS transactions_row_count FROM fact_transactions;
SELECT COUNT(*) AS region_rowcount FROM dim_region;
SELECT COUNT(*) AS date_rows FROM dim_date;
SELECT COUNT(*) AS type_rowcount FROM dim_transactiontype;
SELECT COUNT(*) AS segmentcount FROM dim_customersegment;
SELECT COUNT(*) AS account_rowcount FROM dim_account;
SELECT COUNT(*) AS branch_rowcount FROM dim_branch;
SELECT COUNT(*) AS channel_rowcount FROM dim_channel;
SELECT COUNT(*) AS customer_rowcount FROM dim_customer;
SELECT COUNT(DISTINCT CustomerKey) AS total_customers FROM dim_customer;
SELECT COUNT(DISTINCT AccountKey) AS total_accounts FROM dim_account;
SELECT COUNT(DISTINCT TransactionID) AS total_transactions FROM fact_transactions;
SELECT SUM(Amount) AS total_amount FROM fact_transactions;
SELECT SUM(FeeIncome) AS Revenue FROM fact_transactions;

-- ------------------------------Data cleaning---------------------------------------------------------------------
-- Duplicates---
SELECT * FROM(
SELECT *,
	ROW_NUMBER() OVER(PARTITION BY TransactionID ORDER BY TransactionID) rn
FROM fact_transactions
)t 
WHERE rn > 1;

CREATE TABLE fact_backup AS SELECT * FROM fact_transactions; -- backup incase deleting goes wrong

TRUNCATE TABLE fact_transactions;
INSERT INTO fact_transactions
WITH Deduplicated AS (
	SELECT *,
	ROW_NUMBER() OVER(PARTITION BY TransactionID ORDER BY TransactionID) rn
FROM fact_backup
)
SELECT TransactionID, DateKey, AccountKey, CustomerKey, BranchKey, ChannelKey, TransactionTypeKey,
		Amount, Status, SuspiciousFlag, FraudFlag, FeeIncome
FROM Deduplicated
WHERE rn = 1;
-- ---Nulls/ blanks in columns
SELECT * FROM fact_backup
WHERE TransactionID IS NULL 
	OR DateKey IS NULL OR AccountKey IS NULL 
	OR CustomerKey IS NULL OR BranchKey IS NULL 
    OR ChannelKey IS NULL OR TransactionTypeKey IS NULL 
    OR Amount IS NULL OR Amount = '' or Status IS NULL OR Status = '' 
    OR SuspiciousFlag IS null OR FraudFlag IS NULL OR FeeIncome IS NULL OR FeeIncome = '';
    
ALTER TABLE fact_transactions 
ADD COLUMN AmountMissing VARCHAR(4) DEFAULT 'No';
UPDATE fact_transactions
SET AmountMissing = 'Yes'
WHERE Amount IS NULL OR Amount = '';
UPDATE fact_transactions
SET Amount = NULL 
WHERE Amount = ''; 
DELETE FROM fact_transactions WHERE Amount IS NULL;
-- Date range ( should be bewtween Jan 2025 and Aug 2026
SELECT MIN(DateKey), MAX(DateKey) FROM fact_transactions; 
SELECT MIN(DateKey), MAX(DateKey) FROM dim_date;   
-- Trimming and standardization
SELECT * FROM fact_transactions
WHERE TRIM(Status) = '' OR TRIM(SuspiciousFlag) = '' OR TRIM(FraudFlag) = '';
UPDATE fact_transactions
SET Status = TRIM(Status),
	SuspiciousFlag = TRIM(SuspiciousFlag),
    FraudFlag = TRIM(FraudFlag);
UPDATE dim_customer
SET DataExposed = TRIM(DataExposed),
	status = TRIM(status),
    segment = TRIM(segment);
UPDATE dim_account
SET AccountType = TRIM(AccountType),
	status = TRIM(status);
UPDATE dim_region
SET region = TRIM(region),
	state = TRIM(state);

-- outliers detection
SELECT MIN(Amount), MAX(Amount), AVG(Amount), SUM(Amount <=0) AS zero_or_negative
FROM fact_transactions
WHERE Amount IS NOT NULL;
SELECT * FROM fact_transactions
ORDER BY FeeIncome DESC
LIMIT 30;

WITH R AS (
	SELECT Amount,
    ROW_NUMBER() OVER(ORDER BY Amount)rn,
    COUNT(*) OVER() n 
    FROM fact_transactions 
    WHERE Amount IS NOT NULL),
Q AS (
	SELECT MIN(CASE WHEN rn >= n*0.25 THEN Amount END) q1,
			MIN(CASE WHEN rn >=n*0.75 THEN Amount END) q3
            FROM R)
	SELECT q1, q3, q3 + 1.5*(q3-q1) AS upper_fence,
		(SELECT COUNT(*) FROM fact_transactions, Q
        WHERE Amount > Q.q3 + 1.5*(Q.q3-Q.q1)) AS Outlier_count
	FROM Q;
    
    WITH R AS (
	SELECT FeeIncome,
    ROW_NUMBER() OVER(ORDER BY FeeIncome)rn,
    COUNT(*) OVER() n 
    FROM fact_transactions 
    WHERE FeeIncome IS NOT NULL),
Q AS (
	SELECT MIN(CASE WHEN rn >= n*0.25 THEN FeeIncome END) q1,
			MIN(CASE WHEN rn >=n*0.75 THEN FeeIncome END) q3
            FROM R)
	SELECT q1, q3, q3 + 1.5*(q3-q1) AS upper_fence,
		(SELECT COUNT(*) FROM fact_transactions, Q
        WHERE FeeIncome > q3 + 1.5*(q3-q1)) AS Outlier_count
	FROM Q;

SELECT * FROM fact_transactions
WHERE Amount > 183508.925
ORDER BY Amount DESC;

SELECT t.TransactionType, COUNT(*), MIN(f.Amount), ROUND(AVG(f.Amount), 2) avg_amt, MAX(f.Amount)
FROM fact_transactions f 
JOIN dim_transactiontype t 
	ON f.TransactionTypeKey = t.TransactionTypeKey
WHERE Amount IS NOT NULL
GROUP BY t.TransactionType 
ORDER BY avg_amt DESC;

SELECT FraudFlag, COUNT(*), MIN(Amount), ROUND(AVG(Amount), 2) avg_amt, MAX(Amount)
FROM fact_transactions 
GROUP BY FraudFlag;
-- numerical valuess
SELECT MIN(FeeIncome), MAX(FeeIncome), AVG(FeeIncome), SUM(FeeIncome <=0) AS zero_or_negative
FROM fact_transactions;
SELECT * FROM dim_customer
WHERE Age <=0;
SELECT MIN(Balance), MAX(Balance), AVG(Balance), SUM(Balance <=0) AS zero_or_negative
FROM dim_account; 
-- text spellings
SELECT DISTINCT SuspiciousFlag FROM fact_transactions;
SELECT DISTINCT FraudFlag FROM fact_transactions;
SELECT DISTINCT Status FROM dim_account;
SELECT DISTINCT AccountType FROM dim_account;
SELECT DISTINCT Channel FROM dim_channel;
-- Changing data types
ALTER TABLE fact_transactions
MODIFY COLUMN TransactionID VARCHAR(10), MODIFY COLUMN DateKey DATE, MODIFY COLUMN AccountKey VARCHAR(10),
MODIFY COLUMN CustomerKey VARCHAR(10), Modify column BranchKey VARCHAR(10), MODIFY COLUMN ChannelKey VARCHAR(10),
MODIFY COLUMN TransactionTypeKey VARCHAR(10), MODIFY COLUMN Status VARCHAR(10), MODIFY COLUMN SuspiciousFlag VARCHAR(10),
MODIFY COLUMN FraudFlag VARCHAR (10), MODIFY COLUMN Amount DECIMAL(15,2), MODIFY COLUMN FeeIncome DECIMAL(12,2);
ALTER TABLE dim_transactiontype
MODIFY COLUMN TransactionTypeKey VARCHAR(10), MODIFY COLUMN TransactionType VARCHAR(20);
ALTER TABLE dim_region
MODIFY COLUMN RegionKey VARCHAR(10), MODIFY COLUMN Region VARCHAR(20), MODIFY COLUMN State VARCHAR(10);
ALTER TABLE dim_date
MODIFY COLUMN DateKey DATE, MODIFY COLUMN Year INT, MODIFY COLUMN Quarter VARCHAR(5), MODIFY COLUMN Month VARCHAR(20), 
MODIFY COLUMN MonthNumber TINYINT, MODIFY COLUMN YearMonth VARCHAR(10);
ALTER TABLE dim_customersegment
MODIFY COLUMN SegmentKey VARCHAR(10), MODIFY COLUMN Segment VARCHAR(20);
ALTER TABLE dim_customer
MODIFY COLUMN CustomerKey VARCHAR(10), MODIFY COLUMN CustomerName VARCHAR(20), MODIFY COLUMN Segment VARCHAR(10),
MODIFY COLUMN Status VARCHAR(10), MODIFY COLUMN DataExposed VARCHAR(10), MODIFY COLUMN Age INT;
ALTER TABLE dim_channel
MODIFY COLUMN ChannelKey VARCHAR(10), MODIFY COLUMN Channel VARCHAR(20);
ALTER TABLE dim_branch
MODIFY COLUMN BranchKey VARCHAR(10), MODIFY COLUMN BranchName VARCHAR(20), MODIFY COLUMN RegionKey VARCHAR(10);
ALTER TABLE dim_account
MODIFY COLUMN AccountKey VARCHAR(10), MODIFY COLUMN CustomerKey VARCHAR(10), MODIFY COLUMN AccountType VARCHAR(10),
MODIFY COLUMN Status VARCHAR(10), MODIFY COLUMN Balance DECIMAL(15,2);

-- orphan keys
SELECT DISTINCT f.AccountKey 
FROM fact_transactions f
WHERE NOT EXISTS ( 
		SELECT 1
		FROM dim_account d 
        WHERE d.AccountKey = f.AccountKey);
        
SELECT 'CustomerKey' AS key_checked, COUNT(*) AS orphan_rows
FROM fact_transactions f 
WHERE NOT EXISTS ( SELECT 1 FROM dim_customer d WHERE d.CustomerKey = f.CustomerKey)
UNION ALL
SELECT 'AccountKey', COUNT(*) 
FROM fact_transactions f 
WHERE NOT EXISTS ( SELECT 1 FROM dim_account d WHERE d.AccountKey = f.AccountKey)
UNION ALL
SELECT 'BranchKey', COUNT(*) 
FROM fact_transactions f 
WHERE NOT EXISTS ( SELECT 1 FROM dim_branch d WHERE d.BranchKey = f.BranchKey)
UNION ALL
SELECT 'ChannelKey', COUNT(*) 
FROM fact_transactions f 
WHERE NOT EXISTS ( SELECT 1 FROM dim_channel d WHERE d.ChannelKey = f.ChannelKey)
UNION ALL
SELECT 'TransactionTypeKey', COUNT(*)
FROM fact_transactions f 
WHERE NOT EXISTS ( SELECT 1 FROM dim_transactiontype d WHERE d.TransactionTypeKey = f.TransactionTypeKey)
UNION ALL
SELECT 'DateKey', COUNT(*) 
FROM fact_transactions f 
WHERE NOT EXISTS ( SELECT 1 FROM dim_date d WHERE d.DateKey = f.DateKey);

SELECT 'RegionKey', COUNT(*) 
FROM dim_branch b 
WHERE NOT EXISTS ( SELECT 1 FROM dim_region r WHERE r.RegionKey = b.RegionKey);

SELECT CustomerKey
FROM dim_account a 
WHERE NOT EXISTS ( SELECT 1 FROM dim_customer c WHERE a.CustomerKey = c.CustomerKey);

SELECT 'SegmentKey', COUNT(*) 
FROM dim_customer c 
WHERE NOT EXISTS ( SELECT 1 FROM dim_customersegment d WHERE d.Segment = c.Segment);

-- Flag Logic
SELECT 
	COUNT(*) AS total_transactions,
    SUM(SuspiciousFlag = 'Yes') AS SuspiciousCount,
    SUM(FraudFlag = 'Yes') AS FraudCount,
    SUM(CASE WHEN SuspiciousFlag = 'Yes' AND FraudFlag = 'Yes' THEN 1 ELSE 0 END) AS 'ConfirmedFraud',
    SUM(CASE WHEN SuspiciousFlag = 'Yes' AND FraudFlag = 'No' THEN 1 ELSE 0 END) AS 'FalseAlarm',
    SUM(CASE WHEN SuspiciousFlag = 'No' AND FraudFlag = 'Yes' THEN 1 ELSE 0 END) AS 'MissedAlarm',
    SUM(CASE WHEN SuspiciousFlag = 'No' AND FraudFlag = 'No' THEN 1 ELSE 0 END) AS 'Normal'
FROM fact_transactions;
    

-- Post cleaning validation
SELECT COUNT(*) AS transactions_row_count FROM fact_transactions;
SELECT COUNT(*) AS region_rowcount FROM dim_region;
SELECT COUNT(*) AS date_rows FROM dim_date;
SELECT COUNT(*) AS type_rowcount FROM dim_transactiontype;
SELECT COUNT(*) AS segmentcount FROM dim_customersegment;
SELECT COUNT(*) AS account_rowcount FROM dim_account;
SELECT COUNT(*) AS branch_rowcount FROM dim_branch;
SELECT COUNT(*) AS channel_rowcount FROM dim_channel;
SELECT COUNT(*) AS customer_rowcount FROM dim_customer;
SELECT COUNT(DISTINCT CustomerKey) AS total_customers FROM dim_customer;
SELECT COUNT(DISTINCT AccountKey) AS total_accounts FROM dim_account;
SELECT COUNT(DISTINCT TransactionID) AS total_transactions FROM fact_transactions;
SELECT SUM(Amount) AS total_amount FROM fact_transactions;
SELECT SUM(FeeIncome) AS total_feeIncome FROM fact_transactions;

-- targets-------------------------------
UPDATE targets
SET Month = TRIM(Month),
	RevenueTarget = TRIM(RevenueTarget),
    ProfitTarget = TRIM(ProfitTarget),
    TransactionTarget = TRIM(TransactionTarget),
    MaxFraudCases = TRIM(MaxFraudCases);
UPDATE targets
SET RevenueTarget = REPLACE(RevenueTarget, ',',''),
	ProfitTarget = REPLACE(ProfitTarget, ',','');
ALTER TABLE targets
MODIFY COLUMN Month VARCHAR(7),
MODIFY COLUMN RevenueTarget DECIMAL(15,2),
MODIFY COLUMN ProfitTarget DECIMAL(15,2);


-- ---------------------------------------------ANALYSIS----------------------------------------------------------
-- CEO----------------------------
-- Overall business impact
SELECT 
	COUNT(TransactionID) AS Total_transactions,
    SUM(Amount) AS total_transaction_value,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END) AS FraudCount,
    SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END) AS SuspiciousCount,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END) AS FraudAmount,
    CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END)/SUM(Amount)) * 100, 2), '%') as fraud_value_pct,
    CONCAT(ROUND((SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 2), '%') AS Suspicious_rate,
	CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 2), '%') AS Fraud_rate
FROM fact_transactions;

-- segments most affected
SELECT Segment,
	CONCAT(ROUND((SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Suspicious_rate,
	CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Fraud_rate,
	CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END)/SUM(Amount)) * 100, 1), '%') AS Fraud_value_pct
FROM fact_transactions
JOIN dim_customer
	USING (CustomerKey)
JOIN dim_customersegment
	USING (Segment)
GROUP BY Segment;

-- region/branches that need attention
SELECT BranchName,Region,
	CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END)/SUM(Amount)) * 100, 1), '%') AS Fraud_value_pct,
	CONCAT(ROUND((SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Suspicious_rate,
	CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Fraud_rate
FROM fact_transactions
JOIN dim_branch
	USING (BranchKey)
JOIN dim_region
	USING (RegionKey)
GROUP BY BranchName, Region
ORDER BY Fraud_rate DESC;

SELECT Region,
	CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END)/SUM(Amount)) * 100, 1), '%') AS Fraud_value_pct,
	CONCAT(ROUND((SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Suspicious_rate,
	CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Fraud_rate
FROM fact_transactions
JOIN dim_branch
	USING (BranchKey)
JOIN dim_region
	USING (RegionKey)
GROUP BY Region
ORDER BY Region DESC;

-- activity change/ trend
SELECT 
	YearMonth,
    COUNT(TransactionID) AS Total_transactions,
    COUNT(DISTINCT customerKey) AS active_customers,
    SUM(Amount) AS total_transaction_value,
    AVG(Amount) AS avg_transaction_value,
    CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 2), '%') AS Fraud_rate,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END) AS FraudCount,
    SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END) AS SuspiciousCount,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END) AS FraudAmount,
    CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END)/SUM(Amount)) * 100, 1), '%') as fraud_value_pct
FROM fact_transactions
JOIN dim_date
	USING (DateKey)
GROUP BY YearMonth
ORDER BY YearMonth ASC;

SELECT 
	CASE 
		WHEN DATE_FORMAT(DateKey, '%Y-%m') = '2026-08' THEN 'Post-Incident (Aug 2026)'
        ELSE 'Pre-Incident (Jan 2025 - Jul 2026)'
        END AS Activity_period,
	COUNT(TransactionID) AS Total_transactions,
    COUNT(DISTINCT CustomerKey) AS active_customers,
    SUM(Amount) AS total_transaction_value,
    AVG(Amount) AS avg_transaction_value,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END) AS FraudCount,
    SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END) AS SuspiciousCount,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END) AS FraudAmount,
    CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END)/SUM(Amount)) * 100, 2), '%') as fraud_value_pct,
    CONCAT(ROUND((SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 2), '%') AS Suspicious_rate,
	CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 2), '%') AS Fraud_rate
FROM fact_transactions
GROUP BY Activity_period
ORDER BY Activity_period DESC;

WITH Monthly AS (
	SELECT DATE_FORMAT(DateKey, '%Y-%m') AS YearMonth,
	CASE WHEN DATE_FORMAT(DateKey, '%Y-%m') = '2026-08' THEN 'Post-Incident (Aug 2026)'
        ELSE 'Pre-Incident (Jan 2025 - Jul 2026)' END AS Activity_period,
	COUNT(*) AS txns,
    COUNT(DISTINCT CustomerKey) AS active_customers,
    SUM(Amount) AS total_txn_value,
    COUNT(Amount) AS amt_n,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END) AS FraudCount,
    SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END) AS SuspiciousCount,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END) AS FraudAmount,
    CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END)/SUM(Amount)) * 100, 2), '%') as fraud_value_pct
FROM fact_transactions
GROUP BY YearMonth, Activity_period
)
SELECT Activity_period,
ROUND(AVG(txns)) AS avg_monthly_txns,
ROUND(AVG(active_customers)) AS avg_monthly_active_customers,
ROUND(SUM(total_txn_value)/SUM(amt_n),2) AS avg_transaction_value,
ROUND(AVG(FraudCount),1) AS avg_fraudCount,
ROUND(AVG(FraudAmount),2) AS avg_FraudAmount,
ROUND(SUM(SuspiciousCount)/SUM(txns) * 100, 2) AS Suspicious_rate,
ROUND(SUM(FraudCount)/SUM(txns) * 100, 2) AS Fraud_rate
FROM Monthly
GROUP BY Activity_period;


-- CRO---------------------------------
-- segments with highest exposure
SELECT Segment,
	COUNT(DISTINCT CASE WHEN DataExposed = 'Yes' THEN CustomerKey END) AS Customers_exposed,
    COUNT(DISTINCT CustomerKey) AS Total_customers,
    CONCAT(ROUND(COUNT(DISTINCT CASE WHEN DataExposed = 'Yes' THEN CustomerKey END)/COUNT(DISTINCT CustomerKey) * 100, 1), '%')
		AS pct_exposed,
	CONCAT(ROUND((SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Suspicious_rate,
	CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Fraud_rate
FROM dim_customer
LEFT JOIN fact_transactions
	USING (CustomerKey)
GROUP BY Segment;

-- Channels with most suspicious activity
SELECT 
	Channel,
    SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END) AS Suspicious_count,
    CONCAT(ROUND((SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Suspicious_rate
FROM fact_transactions
JOIN dim_channel
	USING (ChannelKey)
GROUP BY Channel
ORDER BY Suspicious_rate DESC;

-- transaction types with most fraudulent activity
SELECT 
	TransactionType,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END) AS Fraud_count,
    CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Fraud_rate
FROM fact_transactions
JOIN dim_transactiontype
	USING (TransactionTypeKey)
GROUP BY TransactionType
ORDER BY Fraud_rate DESC;

-- Data exposed for the whole period of jan 2025 - aug 2026
SELECT 
	COUNT(CustomerKey) AS Customers_exposed
FROM dim_customer
WHERE DataExposed = 'Yes';

SELECT 
	DataExposed,
    COUNT(TransactionID) AS Total_transactions,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END) AS FraudCount,
    SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END) AS SuspiciousCount,
    CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Fraud_rate,
    CONCAT(ROUND((SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Suspicious_rate
FROM fact_transactions 
JOIN dim_customer
	USING (CustomerKey)
GROUP BY DataExposed;

-- data exposed just for aug 2026
SELECT 
	DataExposed,
    COUNT(TransactionID) AS Total_transactions,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END) AS FraudCount,
    SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END) AS SuspiciousCount,
    CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Fraud_rate,
    CONCAT(ROUND((SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Suspicious_rate
FROM fact_transactions 
JOIN dim_customer
	USING (CustomerKey)
JOIN dim_date
	USING (DateKey)
WHERE DateKey >= '2026-08-01'
GROUP BY DataExposed;

-- Major risk hotspots- branch, age, channel
SELECT 
	Channel,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END) AS Fraud_count,
    CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Fraud_rate,
    SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END) AS Suspicious_count,
    CONCAT(ROUND((SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Suspicious_rate
FROM fact_transactions
JOIN dim_channel
	USING (ChannelKey)
GROUP BY Channel
ORDER BY Fraud_rate DESC;

SELECT 
	TransactionType,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END) AS Fraud_count,
    CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Fraud_rate,
    SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END) AS Suspicious_count,
    CONCAT(ROUND((SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Suspicious_rate
FROM fact_transactions
JOIN dim_transactiontype
	USING (TransactionTypeKey)
GROUP BY TransactionType
ORDER BY Fraud_rate DESC;

SELECT 
	BranchName,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END) AS Fraud_count,
    CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Fraud_rate,
    SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END) AS Suspicious_count,
    CONCAT(ROUND((SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Suspicious_rate
FROM fact_transactions
JOIN dim_branch
	USING (BranchKey)
GROUP BY BranchName
ORDER BY Fraud_rate DESC;
SELECT MIN(age), MAX(Age), COUNT(*) FROM dim_customer;
WITH Customer_age AS (
	SELECT 
		CustomerKey,
		CASE WHEN Age BETWEEN 18 AND 24 THEN '18-24' 
			WHEN Age BETWEEN 25 AND 34 THEN '25-34' 
			WHEN Age BETWEEN 35 AND 44 THEN '35-44'
			WHEN Age BETWEEN 45 AND 54 THEN '45-54'
            WHEN Age BETWEEN 55 AND 64 THEN '55-64'
			ELSE '65+' END AS Age_group
	FROM dim_customer
)
SELECT c.Age_group,
	COUNT(DISTINCT c.CustomerKey) as customers,
	SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END) AS Fraud_count,
    CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Fraud_rate,
    SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END) AS Suspicious_count,
    CONCAT(ROUND((SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Suspicious_rate
FROM fact_transactions f
LEFT JOIN Customer_age c 
	ON f.CustomerKey = c.CustomerKey
GROUP BY c.Age_group
ORDER BY c.Age_group;
SELECT COUNT(DISTINCT CustomerKey) from fact_transactions;

SELECT a.Status as account_status,

	SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END) AS Fraud_count,
    CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Fraud_rate,
    SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END) AS Suspicious_count,
    CONCAT(ROUND((SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 1), '%') AS Suspicious_rate
FROM fact_transactions f
JOIN dim_account a
	USING (AccountKey)
GROUP BY a.Status;

-- Flag Logic
SELECT 
	COUNT(*) AS total_transactions,
    SUM(SuspiciousFlag = 'Yes') AS SuspiciousCount,
    SUM(FraudFlag = 'Yes') AS FraudCount,
    SUM(CASE WHEN SuspiciousFlag = 'Yes' AND FraudFlag = 'Yes' THEN 1 ELSE 0 END) AS 'ConfirmedFraud',
    SUM(CASE WHEN SuspiciousFlag = 'Yes' AND FraudFlag = 'No' THEN 1 ELSE 0 END) AS 'FalseAlarm',
    SUM(CASE WHEN SuspiciousFlag = 'No' AND FraudFlag = 'Yes' THEN 1 ELSE 0 END) AS 'MissedAlarm',
    SUM(CASE WHEN SuspiciousFlag = 'No' AND FraudFlag = 'No' THEN 1 ELSE 0 END) AS 'Normal'
FROM fact_transactions;
    
SELECT Status,
		SUM(FraudFlag = 'Yes') AS fraud_count,
        SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END) AS fraud_amount
FROM fact_transactions
GROUP BY Status;
-- Areas that require immediate monitoring - Corporate customers, Mobile/Branch, Closed/Dormant accounts
-- CFO-----------===============================
-- Financial impact of fraud
SELECT
	SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END) AS FraudAmount
FROM fact_transactions;

-- fraud amount by transaction type
SELECT 
	TransactionType,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END) AS FraudAmount
FROM fact_transactions
JOIN dim_transactiontype
	USING (TransactionTypeKey)
GROUP BY TransactionType
ORDER BY FraudAmount DESC;

-- fraud amount by region
SELECT 
	Region,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END) AS FraudAmount
FROM fact_transactions
JOIN dim_branch
	USING (BranchKey)
JOIN dim_region
	USING (RegionKey)
GROUP BY Region
ORDER BY FraudAmount DESC;

-- fraud amount by branch
SELECT 
	BranchName,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END) AS FraudAmount
FROM fact_transactions
JOIN dim_branch
	USING (BranchKey)
GROUP BY BranchName
ORDER BY FraudAmount DESC;
    
-- how does actual performance compare with targets
WITH Actual_Vs_Targets AS (
	SELECT 
		DATE_FORMAT(DateKey, '%Y-%m') AS Month,
		COUNT(*) AS actual_transactions,
		SUM(FeeIncome) AS actual_revenue,
		SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END) AS actual_FraudCases
	FROM fact_transactions
	GROUP BY DATE_FORMAT(DateKey, '%Y-%m')
)
SELECT 
	a.Month, a.actual_transactions, t.TransactionTarget, a.actual_revenue, t.RevenueTarget, a.actual_FraudCases, 
    t.MaxFraudCases, CONCAT(ROUND((a.actual_revenue/t.RevenueTarget * 100),1),'%') AS pct_of_revenuetarget,
    CONCAT(ROUND((a.actual_transactions/t.TransactionTarget * 100),1), '%') AS pct_of_TransactionTarget,
    CONCAT(ROUND((a.actual_FraudCases/t.MaxFraudCases * 100), 1), '%') AS pct_of_FraudTarget
FROM Actual_Vs_Targets a 
JOIN targets t 
	ON a.Month = t.Month
ORDER BY a.Month;

-- greates opportunity to reduce losses 
SELECT r.region, c.Segment, t.TransactionType, ch.channel,
	COUNT(TransactionID) AS Total_transactions,
    COUNT(DISTINCT CustomerKey) AS active_customers,
    SUM(Amount) AS total_transaction_value,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END) AS FraudCount,
    SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END) AS SuspiciousCount,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END) AS FraudLossAmount,
    CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END)/SUM(Amount)) * 100, 2), '%') as fraud_value_pct,
    CONCAT(ROUND((SUM(CASE WHEN SuspiciousFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 2), '%') AS Suspicious_rate,
	CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 2), '%') AS Fraud_rate
FROM fact_transactions f 
JOIN dim_customer c 
	USING (CustomerKey)
JOIN dim_branch b 
	USING (BranchKey)
JOIN dim_region r 
	USING (RegionKey)
JOIN dim_transactiontype t
	USING (TransactionTypeKey)
JOIN dim_channel ch 
	USING (ChannelKey)
GROUP BY r.region, c.Segment, t.TransactionType, ch.channel
ORDER BY FraudLossAmount DESC;

SELECT r.region, c.Segment,
	COUNT(TransactionID) AS Total_transactions,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END) AS FraudCount,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END) AS FraudLossAmount,
    CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END)/SUM(Amount)) * 100, 2), '%') as fraud_value_pct,
	CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 2), '%') AS Fraud_rate
FROM fact_transactions f 
JOIN dim_customer c 
	USING (CustomerKey)
JOIN dim_branch b 
	USING (BranchKey)
JOIN dim_region r 
	USING (RegionKey)
GROUP BY r.region, c.Segment
ORDER BY FraudLossAmount DESC;

SELECT r.region, ch.channel,
	COUNT(TransactionID) AS Total_transactions,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END) AS FraudCount,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END) AS FraudLossAmount,
    CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END)/SUM(Amount)) * 100, 2), '%') as fraud_value_pct,
	CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 2), '%') AS Fraud_rate
FROM fact_transactions f 
JOIN dim_customer c 
	USING (CustomerKey)
JOIN dim_branch b 
	USING (BranchKey)
JOIN dim_region r 
	USING (RegionKey)
JOIN dim_channel ch 
	USING (ChannelKey)
GROUP BY r.region, ch.channel
ORDER BY FraudLossAmount DESC;

SELECT c.Segment, t.TransactionType,
	COUNT(TransactionID) AS Total_transactions,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END) AS FraudCount,
    SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END) AS FraudLossAmount,
    CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN Amount ELSE 0 END)/SUM(Amount)) * 100, 2), '%') as fraud_value_pct,
	CONCAT(ROUND((SUM(CASE WHEN FraudFlag = 'Yes' THEN 1 ELSE 0 END)/COUNT(TransactionID)) * 100, 2), '%') AS Fraud_rate
FROM fact_transactions f 
JOIN dim_customer c 
	USING (CustomerKey)
JOIN dim_transactiontype t
	USING (TransactionTypeKey)
GROUP BY c.Segment, t.TransactionType
ORDER BY FraudLossAmount DESC;