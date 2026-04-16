# Index Order Matters - PostgreSQL Challenge

## Overview
This challenge demonstrates why the **column order in a composite index** significantly affects query performance. Even when an index exists, PostgreSQL cannot use it efficiently if the column order doesn't match the query's filtering pattern.

## Key Concept: The Left-Most Prefix Rule

In PostgreSQL, composite indexes follow the **Left-Most Prefix Rule**:
- An index on columns `(A, B, C)` can efficiently satisfy queries that filter on:
  - `A`
  - `A AND B`
  - `A AND B AND C`
- But it **CANNOT** efficiently satisfy queries that filter on:
  - `B` (missing the left-most column)
  - `B AND C` (missing the left-most column)
  - `C` (missing the left-most columns)

## Prerequisites

1. **PostgreSQL** installed and running
2. **psql** command-line tool available
3. Access to create a new database

## Setup Instructions

### Step 1: Install PostgreSQL
**Windows:**
```bash
# Download from https://www.postgresql.org/download/windows/
# Or use Chocolatey:
choco install postgresql14
```

**macOS (using Homebrew):**
```bash
brew install postgresql@14
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt-get update
sudo apt-get install postgresql postgresql-contrib
```

### Step 2: Start PostgreSQL Service
**Windows:**
```bash
# PostgreSQL typically runs as a Windows service automatically
# Check Services app or run:
pg_ctl status -D "C:\Program Files\PostgreSQL\14\data"
```

**macOS/Linux:**
```bash
# Start the service
brew services start postgresql@14
# Or
sudo systemctl start postgresql
```

### Step 3: Create Database and Load Schema
```bash
# Connect to PostgreSQL (you'll be prompted for password)
psql -U postgres

# Once in psql, create the database
CREATE DATABASE index_challenge;

# Exit psql
\q
```

### Step 4: Load the Setup SQL
```bash
# From the project directory
psql -U postgres -d index_challenge -f setup.sql
```

You should see output showing the table structure and indexes created.

## Running the Challenge

### Step 1: Run the Initial Query with EXPLAIN ANALYZE

```bash
psql -U postgres -d index_challenge -f queries.sql
```

**Expected Output (with incorrect index):**
```
QUERY PLAN
─────────────────────────────────────────────
Seq Scan on users  (cost=0.00..35.50 rows=333)
  Filter: ((status = 'active'::text) AND (country = 'USA'::text))
Planning Time: 0.123 ms
Execution Time: 0.445 ms
```

Notice the **Seq Scan** (Sequential Scan) - the index is NOT being used!

### Step 2: Observe the Problem

Run individual queries to understand the issue:

```bash
psql -U postgres -d index_challenge

-- Check current indexes
\di

-- Run the query with the incorrect index
EXPLAIN ANALYZE
SELECT id, username, status, country
FROM users
WHERE status = 'active' AND country = 'USA';
```

### Step 3: Fix the Index

In the `queries.sql` file, the corrected index `idx_users_correct` is created with the proper column order.

**Expected Output (with correct index):**
```
QUERY PLAN
──────────────────────────────────────────────────
Index Scan using idx_users_correct on users  
  Index Cond: ((status = 'active'::text) AND (country = 'USA'::text))
Planning Time: 0.098 ms
Execution Time: 0.123 ms
```

Notice the **Index Scan** - much faster! Execution time drops significantly.

## Interactive Step-by-Step Testing

Open `psql` and run these commands in order:

```bash
psql -U postgres -d index_challenge
```

**Test 1: Current Indexes**
```sql
-- View all indexes on the users table
\di+ users
```

**Test 2: Query with Incorrect Index (Sequential Scan)**
```sql
-- This uses idx_users_incorrect (country, status)
EXPLAIN ANALYZE
SELECT id, username, status, country
FROM users
WHERE status = 'active' AND country = 'USA'
ORDER BY created_at DESC;
```

**Test 3: Create Correct Index**
```sql
-- Drop the incorrect index
DROP INDEX IF EXISTS idx_users_incorrect;

-- Create the correct index
CREATE INDEX idx_users_correct ON users (status, country);
```

**Test 4: Query with Correct Index (Index Scan)**
```sql
-- Now run the same query with the correct index
EXPLAIN ANALYZE
SELECT id, username, status, country
FROM users
WHERE status = 'active' AND country = 'USA'
ORDER BY created_at DESC;
```

**Performance Comparison:**
Compare the "Execution Time" from Test 2 and Test 4. The correct index should be significantly faster.

## Understanding the Results

### Incorrect Index: (country, status)
```
Seq Scan on users  (cost=0.00..35.50 rows=333)
  Filter: ((status = 'active'::text) AND (country = 'USA'::text))
```
- PostgreSQL scans every row in the table
- Applies the WHERE filters to each row
- No index usage - very inefficient for large tables

### Correct Index: (status, country)
```
Index Scan using idx_users_correct on users
  Index Cond: ((status = 'active'::text) AND (country = 'USA'::text))
```
- PostgreSQL uses the index to find matching rows directly
- No full table scan needed
- Much faster for large datasets

## Key Takeaways

1. **Column order matters**: `(A, B)` is NOT the same as `(B, A)`
2. **Left-Most Prefix Rule**: Index must start with the first column used in the WHERE clause
3. **Query Patterns**: Design indexes based on your actual query patterns
4. **Verify with EXPLAIN**: Always use `EXPLAIN ANALYZE` to verify index usage
5. **Performance Matters**: A single misplaced column in an index can turn an O(log n) operation into O(n)

## Troubleshooting

**Problem:** `psql: command not found`
**Solution:** Add PostgreSQL bin directory to PATH:
```bash
export PATH="/usr/local/pgsql/bin:$PATH"
```

**Problem:** `FATAL: authentication failed for user "postgres"`
**Solution:** Check PostgreSQL password or use peer authentication

**Problem:** `FATAL: database "index_challenge" does not exist`
**Solution:** Run the setup.sql file to create the database first

**Problem:** Indexes not appearing in EXPLAIN output
**Solution:** Ensure you ran the `setup.sql` file correctly and the table has data

## Final Notes

This challenge teaches a critical database optimization skill. In production systems:
- Slow queries are often caused by missing or incorrectly ordered indexes
- `EXPLAIN ANALYZE` is your best friend for query optimization
- Test your indexes with realistic data volumes
- Composite indexes should match your query's filtering order
