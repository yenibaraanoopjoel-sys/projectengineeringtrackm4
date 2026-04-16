-- PRACTICAL TESTING SCRIPT
-- Run these commands step-by-step in psql to see the index ordering challenge in action

-- ============================================================================
-- STEP 1: SETUP - Create database and tables
-- ============================================================================

-- Create the database (if not already created via setup.sql)
-- CREATE DATABASE index_challenge;

-- Connect to the database
-- \c index_challenge;

-- Verify the table exists with the correct data
SELECT COUNT(*) as total_rows FROM users;
SELECT COUNT(*) FILTER (WHERE status = 'active') as active_users FROM users;
SELECT COUNT(*) FILTER (WHERE country = 'USA') as usa_users FROM users;

-- ============================================================================
-- STEP 2: EXAMINE CURRENT INDEXES
-- ============================================================================

-- List all indexes on the users table with detailed info
SELECT indexname, indexdef 
FROM pg_indexes 
WHERE tablename = 'users' 
ORDER BY indexname;

-- Get even more detailed index statistics
\di+ users

-- ============================================================================
-- STEP 3: TEST QUERY WITH INCORRECT INDEX
-- ============================================================================
-- This test uses idx_users_incorrect (country, status)
-- Expected: SEQUENTIAL SCAN (bad performance)

EXPLAIN ANALYZE
SELECT id, username, email, status, country, created_at, last_login
FROM users
WHERE status = 'active' 
  AND country = 'USA'
ORDER BY created_at DESC;

-- ANALYSIS POINTS:
-- Look for: "Seq Scan on users" in the output
-- This means PostgreSQL is scanning the entire table
-- Not using the index efficiently

-- Create a simpler version to clearly see the sequential scan
EXPLAIN (FORMAT JSON)
SELECT id, username, status, country
FROM users
WHERE status = 'active' AND country = 'USA';

-- ============================================================================
-- STEP 4: DROP INCORRECT INDEX AND CREATE CORRECT ONE
-- ============================================================================

-- Check if the incorrect index exists
SELECT indexname FROM pg_indexes 
WHERE tablename = 'users' AND indexname = 'idx_users_incorrect';

-- Drop the incorrect index
DROP INDEX IF EXISTS idx_users_incorrect CASCADE;

-- Verify it's gone
\di+ users

-- Create the CORRECT index with proper column order
CREATE INDEX idx_users_correct ON users (status, country);

-- Verify it was created
\di+ users

-- ============================================================================
-- STEP 5: TEST SAME QUERY WITH CORRECT INDEX
-- ============================================================================
-- Expected: INDEX SCAN (good performance)

EXPLAIN ANALYZE
SELECT id, username, email, status, country, created_at, last_login
FROM users
WHERE status = 'active' 
  AND country = 'USA'
ORDER BY created_at DESC;

-- ANALYSIS POINTS:
-- Look for: "Index Scan using idx_users_correct on users"
-- Look for: "Planning Time" and "Execution Time"
-- Compare with the previous run

-- ============================================================================
-- STEP 6: VERIFY LEFT-MOST PREFIX PRINCIPLE
-- ============================================================================

-- Test 1: Using only the first column (status)
-- This should use the index efficiently
EXPLAIN (FORMAT JSON)
SELECT COUNT(*) as active_count
FROM users
WHERE status = 'active';

-- Test 2: Using both columns in order
-- This should use the index very efficiently
EXPLAIN (FORMAT JSON)
SELECT COUNT(*) as active_usa_count
FROM users
WHERE status = 'active' AND country = 'USA';

-- Test 3: Using only the second column (country) without status
-- This should NOT use the index (sequential scan needed)
EXPLAIN (FORMAT JSON)
SELECT COUNT(*) as usa_count
FROM users
WHERE country = 'USA';

-- ============================================================================
-- STEP 7: PERFORMANCE METRICS COMPARISON
-- ============================================================================

-- Get query statistics
-- Note: You may need to enable query_log for this to work

-- First, let's see the index size
SELECT 
    indexrelname,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
WHERE relname = 'users'
ORDER BY indexrelname;

-- Get detailed statistics about index usage
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan as index_scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_returned
FROM pg_stat_user_indexes
WHERE tablename = 'users'
ORDER BY idx_scan DESC;

-- ============================================================================
-- STEP 8: PRACTICAL EXAMPLES - More Queries
-- ============================================================================

-- Query A: Find all active users (uses index, left-most prefix)
EXPLAIN ANALYZE
SELECT username, email, created_at
FROM users
WHERE status = 'active'
LIMIT 10;

-- Query B: Find all active users from Canada (uses index fully)
EXPLAIN ANALYZE
SELECT username, email, created_at
FROM users
WHERE status = 'active' AND country = 'Canada'
LIMIT 10;

-- Query C: Find all users who are inactive (uses index)
EXPLAIN ANALYZE
SELECT username, email, created_at
FROM users
WHERE status = 'inactive'
LIMIT 10;

-- Query D: Find users by country only (CANNOT use index efficiently)
EXPLAIN ANALYZE
SELECT username, email, created_at
FROM users
WHERE country = 'USA'
LIMIT 10;

-- ============================================================================
-- STEP 9: MANUAL PERFORMANCE TEST
-- ============================================================================

-- To test actual execution time, wrap queries in timing

-- Method 1: Using \timing command
\timing on

SELECT id, username, status, country
FROM users
WHERE status = 'active' AND country = 'USA'
ORDER BY created_at DESC;

\timing off

-- Method 2: Using benchmark function (if available)
-- SELECT * FROM pgbench_accounts WHERE aid = 100;

-- ============================================================================
-- STEP 10: CLEANUP (Optional)
-- ============================================================================

-- To reset and try again, run this:
-- DROP INDEX IF EXISTS idx_users_correct CASCADE;
-- CREATE INDEX idx_users_incorrect ON users (country, status);
-- Then repeat from STEP 2

-- ============================================================================
-- KEY OBSERVATIONS SUMMARY
-- ============================================================================

/*
BEFORE (incorrect index idx_users_incorrect):
- Index structure: (country, status)
- Query predicate: WHERE status = 'active' AND country = 'USA'
- Result: SEQ SCAN - Full table scan required
- Cost: O(n) where n = total rows

AFTER (correct index idx_users_correct):
- Index structure: (status, country)
- Query predicate: WHERE status = 'active' AND country = 'USA'
- Result: INDEX SCAN - Efficient index navigation
- Cost: O(log n + k) where n = total rows, k = matching rows

The EXACT SAME QUERY, just with the index column order fixed,
can be 3-55x faster depending on table size!
*/
