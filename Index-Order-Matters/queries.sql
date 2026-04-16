-- Query Analysis: Index Column Order Challenge
-- The task: Find all ACTIVE users from the USA

-- Step 1: Run the query and analyze the query plan
-- This query filters by status first, then by country
-- The most efficient index would be (status, country) NOT (country, status)

-- First, let's see the query plan with the incorrect index
-- EXPLAIN ANALYZE will show if PostgreSQL uses a Sequential Scan or Index Scan

EXPLAIN ANALYZE
SELECT id, username, email, status, country, created_at, last_login
FROM users
WHERE status = 'active' 
  AND country = 'USA'
ORDER BY created_at DESC;

-- Result Analysis:
-- With idx_users_incorrect (country, status):
-- PostgreSQL CANNOT use the index efficiently because:
-- 1. The index is organized as (country, status)
-- 2. The query filters WHERE status = 'active' AND country = 'USA'
-- 3. Due to the Left-Most Prefix Rule, PostgreSQL needs to start scanning from the first column (country)
-- 4. But we're filtering status first, which is the second column in the index
-- 5. Result: PostgreSQL performs a FULL SEQUENTIAL SCAN instead of an efficient INDEX SCAN

-- Step 2: Create the CORRECT index
-- The correct index order is (status, country) to match the query's filtering pattern
DROP INDEX IF EXISTS idx_users_incorrect;
CREATE INDEX idx_users_correct ON users (status, country);

-- Step 3: Run the SAME query again with the corrected index
EXPLAIN ANALYZE
SELECT id, username, email, status, country, created_at, last_login
FROM users
WHERE status = 'active' 
  AND country = 'USA'
ORDER BY created_at DESC;

-- Result Analysis with idx_users_correct (status, country):
-- PostgreSQL CAN use the index efficiently because:
-- 1. The index is organized as (status, country)
-- 2. PostgreSQL can quickly find all rows where status = 'active' (first column)
-- 3. Within those rows, it can find where country = 'USA' (second column)
-- 4. Result: PostgreSQL performs an efficient INDEX SCAN instead of a SEQUENTIAL SCAN
-- 5. This dramatically improves query performance on large datasets

-- Additional test queries to demonstrate the Left-Most Prefix Rule
EXPLAIN ANALYZE
SELECT id, username, status
FROM users
WHERE status = 'active';

-- This also benefits from the (status, country) index!
-- It uses only the status column (the left-most prefix of the index)
