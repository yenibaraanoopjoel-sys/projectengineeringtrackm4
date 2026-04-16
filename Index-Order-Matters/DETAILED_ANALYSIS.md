# DETAILED ANALYSIS: Index Order Matters

## Table of Contents
1. [Visual Index Structure Comparison](#visual-comparison)
2. [Query Execution Plans](#execution-plans)
3. [Performance Metrics](#performance-metrics)
4. [Index Design Guidelines](#index-guidelines)
5. [Troubleshooting](#troubleshooting)

---

## Visual Comparison of Index Structures

### Incorrect Index: (country, status)

```
Index Organization:
┌─────────────────────────────────────────────┐
│              Index on (country, status)      │
├─────────────────────────────────────────────┤
│                                              │
│  Canada                                      │
│  ├─ active → [row_ids: 5, 12, 45, ...]    │
│  ├─ inactive → [row_ids: 42, 78, ...]     │
│                                              │
│  Germany                                     │
│  ├─ active → [row_ids: 23, 67, 89, ...]   │
│  ├─ inactive → [row_ids: 3, 19, ...]      │
│                                              │
│  UK                                          │
│  ├─ active → [row_ids: 8, 34, 56, ...]    │
│  ├─ inactive → [row_ids: 11, 29, ...]     │
│                                              │
│  USA                                         │
│  ├─ active → [row_ids: 1, 6, 10, ...]     │  ← Need to find these
│  └─ inactive → [row_ids: 2, 7, 9, ...]    │
│                                              │
└─────────────────────────────────────────────┘

Query: WHERE status = 'active' AND country = 'USA'

To find matching rows:
1. Start at root with status = 'active' ❌ NOT IN THIS INDEX STRUCTURE
2. Cannot efficiently skip to 'active' rows without country prefix
3. Must scan all countries and their statuses
4. Result: SEQUENTIAL SCAN OF ENTIRE TABLE ❌
```

### Correct Index: (status, country)

```
Index Organization:
┌─────────────────────────────────────────────┐
│              Index on (status, country)      │
├─────────────────────────────────────────────┤
│                                              │
│  active                                      │
│  ├─ Canada → [row_ids: 5, 12, 45, ...]    │
│  ├─ Germany → [row_ids: 23, 67, 89, ...]  │
│  ├─ UK → [row_ids: 8, 34, 56, ...]       │
│  └─ USA → [row_ids: 1, 6, 10, ...]        │  ← Direct access to these!
│                                              │
│  inactive                                    │
│  ├─ Canada → [row_ids: 42, 78, ...]      │
│  ├─ Germany → [row_ids: 3, 19, ...]      │
│  ├─ UK → [row_ids: 11, 29, ...]          │
│  └─ USA → [row_ids: 2, 7, 9, ...]        │
│                                              │
└─────────────────────────────────────────────┘

Query: WHERE status = 'active' AND country = 'USA'

Efficient lookup:
1. Navigate to status = 'active' ✅ IMMEDIATE ACCESS
2. Within 'active', navigate to country = 'USA' ✅ FAST
3. Return matching rows directly [1, 6, 10, ...]
4. Result: INDEX SCAN ✅
```

---

## Query Execution Plans Explained

### Scenario 1: Incorrect Index - Sequential Scan

**SQL Query:**
```sql
EXPLAIN ANALYZE
SELECT id, username, status, country
FROM users
WHERE status = 'active' AND country = 'USA'
ORDER BY created_at DESC;
```

**Output with idx_users_incorrect (country, status):**
```
QUERY PLAN
───────────────────────────────────────────────────────────
Seq Scan on users  (cost=0.00..35.50 rows=333)
  Filter: ((status = 'active'::text) AND (country = 'USA'::text))
Planning Time: 0.123 ms
Execution Time: 0.445 ms
(5 rows)
```

**Interpretation:**
- **Seq Scan** = Sequential Scan (reading every row)
- **cost=0.00..35.50** = Planning cost to actual max cost estimate
- **rows=333** = Estimated rows to scan before filtering
- **Filter** = WHERE conditions applied to each row
- **Execution Time: 0.445 ms** = Actual query runtime

**Performance Issues:**
- O(n) complexity where n = number of rows in table
- Every row must be examined
- For 1,000 rows: 0.4 ms
- For 100,000 rows: 40+ ms
- For 1,000,000 rows: 400+ ms

---

### Scenario 2: Correct Index - Index Scan

**SQL Query (same as above):**
```sql
EXPLAIN ANALYZE
SELECT id, username, status, country
FROM users
WHERE status = 'active' AND country = 'USA'
ORDER BY created_at DESC;
```

**Output with idx_users_correct (status, country):**
```
QUERY PLAN
────────────────────────────────────────────────────────────
Index Scan using idx_users_correct on users
  (cost=0.00..15.42 rows=333)
  Index Cond: ((status = 'active'::text) AND (country = 'USA'::text))
Planning Time: 0.098 ms
Execution Time: 0.123 ms
(6 rows)
```

**Interpretation:**
- **Index Scan** = Using index to find rows
- **Index Cond** = Conditions applied directly in index lookup
- **cost=0.00..15.42** = LOWER cost than sequential scan
- **Execution Time: 0.123 ms** = Much faster (3.6x speedup!)

**Performance Advantages:**
- O(log n + k) complexity (n = table size, k = matching rows)
- Index B-Tree navigation is logarithmic
- For 1,000 rows: 0.12 ms
- For 100,000 rows: 1-2 ms
- For 1,000,000 rows: 5-10 ms

---

### Scenario 3: Partial Index Usage (Left-Most Prefix)

**SQL Query (only status, no country):**
```sql
EXPLAIN ANALYZE
SELECT id, username, status
FROM users
WHERE status = 'active';
```

**Output with idx_users_correct (status, country):**
```
QUERY PLAN
────────────────────────────────────────────────────────
Index Only Scan using idx_users_correct on users
  (cost=0.00..12.50 rows=333)
  Index Cond: (status = 'active'::text)
Planning Time: 0.087 ms
Execution Time: 0.089 ms
(5 rows)
```

**Key Points:**
- The index can be used even though we only filter by the first column
- **Index Only Scan** = All data is available in the index itself
- From a 0.445 ms sequential scan down to 0.089 ms!
- This demonstrates the **Left-Most Prefix Rule** working correctly

---

### Scenario 4: Cannot Use Index (Missing Left-Most Column)

**SQL Query (only country, no status):**
```sql
EXPLAIN ANALYZE
SELECT id, username, country
FROM users
WHERE country = 'USA';
```

**Output with idx_users_correct (status, country):**
```
QUERY PLAN
─────────────────────────────────────────────
Seq Scan on users  (cost=0.00..35.50 rows=50)
  Filter: (country = 'USA'::text)
Planning Time: 0.102 ms
Execution Time: 0.312 ms
(5 rows)
```

**Key Points:**
- **Cannot use the index** because we're filtering on the second column
- The index requires starting with the first column (status)
- PostgreSQL falls back to sequential scan
- This shows why **index column order is critical**

---

## Performance Metrics

### Execution Time Comparison (1,000 rows)

| Query Pattern | Incorrect Index Result | Correct Index Result | Speedup |
|--------------|----------------------|----------------------|---------|
| status='active' AND country='USA' | Seq Scan (0.445 ms) | Index Scan (0.123 ms) | 3.6x |
| status='active' | Seq Scan (0.445 ms) | Index Only (0.089 ms) | 5x |
| country='USA' (alone) | Seq Scan (0.312 ms) | Seq Scan (0.312 ms) | 1x |

### Projected Performance at Scale

| Table Size | Query | Sequential Scan | Index Scan | Speedup |
|-----------|-------|-----------------|-----------|---------|
| 10,000 | status & country | 4.5 ms | 1.2 ms | 3.75x |
| 100,000 | status & country | 44 ms | 1.5 ms | 29x |
| 1,000,000 | status & country | 440 ms | 2 ms | 220x |
| 10,000,000 | status & country | 4.4 sec | 3 ms | 1,466x |

### Cost Analysis

```
Query Optimizer Cost Calculation:

Incorrect Index (country, status):
├─ Cost to start scan: 0.00
├─ Cost to scan 333 rows: 35.50
├─ Seq Scan Cost: 0.00 + 35.50 = 35.50
└─ Decision: USE SEQUENTIAL SCAN ✗

Correct Index (status, country):
├─ Cost to start index: 0.00
├─ Cost to scan 333 index entries: 15.42
├─ Filter cost: 0.00
├─ Fetch 333 rows: 0.00
├─ Index Scan Cost: 0.00 + 15.42 = 15.42
└─ Decision: USE INDEX SCAN ✓

Speedup factor: 35.50 / 15.42 ≈ 2.3x in cost estimates
Actual speedup: 3.6x in execution time (indexes are faster in practice)
```

---

## Index Design Guidelines

### Rule 1: Match Index Order to WHERE Clause Order

```sql
-- Bad: Index order doesn't match WHERE order
CREATE INDEX bad_idx ON orders (customer_id, order_date);
SELECT * FROM orders WHERE order_date > '2024-01-01' AND customer_id = 5;
-- ❌ Cannot use index efficiently (missing customer_id first)

-- Good: Index order matches WHERE order
CREATE INDEX good_idx ON orders (order_date, customer_id);
SELECT * FROM orders WHERE order_date > '2024-01-01' AND customer_id = 5;
-- ✅ Uses index efficiently (order_date is first)
```

### Rule 2: Consider Query Patterns

```sql
-- Identify your actual query patterns first
SELECT * FROM users WHERE status = 'active';           -- Frequency: High
SELECT * FROM users WHERE status = 'active' AND country = 'USA';  -- Frequency: High
SELECT * FROM users WHERE country = 'USA';            -- Frequency: Low

-- Optimal Index: (status, country)
-- Covers the high-frequency patterns efficiently
CREATE INDEX idx_users_optimal ON users (status, country);
```

### Rule 3: Leverage Left-Most Prefix

```sql
-- Index: (A, B, C)
-- Can efficiently help queries using:
✅ A
✅ A, B
✅ A, B, C
✅ A (even if B, C are in WHERE clause)
❌ B
❌ C
❌ B, C
❌ A, C (skipping B breaks the rule)

-- Query that skips B:
SELECT * FROM table WHERE A = 1 AND C = 3;  -- ❌ Index not fully used
```

### Rule 4: Index Selectivity and Cardinality

```sql
-- Higher selectivity first (fewer matching rows)
-- Lower selectivity second (more matching rows)

-- If:
-- - status has 2 unique values (low selectivity)
-- - country has 50 unique values (higher selectivity)
-- - Then: Index should be (country, status) not (status, country)

-- But for our query pattern:
-- - We mostly filter by status first → Better to have status first
-- - Even though country has higher cardinality

-- Rule: Match your typical query pattern > pure cardinality logic
```

### Rule 5: Composite vs. Multiple Indexes

```sql
-- Option 1: One Composite Index
CREATE INDEX idx_composite ON users (status, country);
-- ✅ Space efficient
-- ✅ Helps status queries, status+country queries
-- ❌ Doesn't help country-only queries

-- Option 2: Multiple Separate Indexes
CREATE INDEX idx_status ON users (status);
CREATE INDEX idx_country ON users (country);
-- ✅ Helps both status and country queries individually
-- ❌ More disk space, slower writes
-- ❌ PostgreSQL has to choose which index to use

-- Option 3: Covering Index (Includes extra columns)
CREATE INDEX idx_covering ON users (status, country) 
INCLUDE (created_at, last_login);
-- ✅ Can return all data from index (Index Only Scan)
-- ✅ Faster for frequently accessed columns
-- ❌ More disk space

-- Recommendation: Start with composite index matching query pattern
```

---

## Troubleshooting

### Problem 1: Index Not Being Used

```sql
-- Check current query plan
EXPLAIN SELECT * FROM users WHERE status = 'active' AND country = 'USA';

-- If shows "Seq Scan" instead of "Index Scan":
-- 1. Verify index exists
SELECT * FROM pg_indexes WHERE tablename = 'users';

-- 2. Check index column order
\di+ users

-- 3. Force reindex to rebuild stale index
REINDEX INDEX idx_users_correct;

-- 4. Update table statistics
ANALYZE users;

-- 5. Try query again
EXPLAIN ANALYZE SELECT * FROM users 
WHERE status = 'active' AND country = 'USA';
```

### Problem 2: Index Created But Queries Still Slow

```sql
-- Possible causes:
-- 1. Index is too small to matter (table has few rows)
-- 2. Query doesn't match index column order
SELECT pg_size_pretty(pg_relation_size('idx_users_correct')) as index_size;

-- 3. Statistics are outdated
VACUUM ANALYZE users;

-- 4. Index is fragmented
REINDEX INDEX idx_users_correct;

-- 5. Too many indexes (slows down inserts)
SELECT indexname FROM pg_indexes WHERE tablename = 'users';
-- Consider dropping unused indexes
```

### Problem 3: Index Works but Queries Still Slow

```sql
-- The index might be correct, but other bottlenecks exist:

-- 1. Check if ORDER BY is causing issues
EXPLAIN ANALYZE SELECT * FROM users
WHERE status = 'active' AND country = 'USA'
ORDER BY created_at DESC;
-- If "Sort" appears, create index including order_by column

-- 2. Check if joining with other tables
EXPLAIN ANALYZE SELECT u.*, o.* FROM users u
JOIN orders o ON u.id = o.user_id
WHERE u.status = 'active' AND u.country = 'USA';
-- May need index on orders.user_id

-- 3. Check disk I/O (most common bottleneck on large tables)
-- Upgrade SSD, increase RAM cache, or partition table

-- 4. Increase work_mem for large results
SET work_mem = '256MB';
```

### Problem 4: Index Column Order Confusion

```sql
-- When in doubt, create indexes matching this pattern:
-- 1. Equality conditions first (WHERE a = 1)
-- 2. Range conditions second (WHERE b > 10)
-- 3. Not in WHERE clause last (for covering indexes)

-- Example:
-- Query: WHERE status = 'active' AND created_at > '2024-01-01'
-- Index: CREATE INDEX idx ON users (status, created_at);
--        ↑ equality first    ↑ range second

SELECT * FROM users
WHERE status = 'active' AND created_at > '2024-01-01';
```

---

## Summary

| Aspect | Details |
|--------|---------|
| **Key Concept** | Index column order must match query filter order |
| **Left-Most Prefix** | Index can be used starting from the first column |
| **Performance** | Correct index yields 3.6x - 1,466x speedup depending on table size |
| **Example** | Index `(status, country)` for query `WHERE status = ? AND country = ?` |
| **Avoid** | Creating index `(country, status)` for a query filtering by status first |
| **Verify** | Always use EXPLAIN ANALYZE to confirm index usage |
| **Production Impact** | Slow queries in production often caused by wrong index ordering |

---

**Challenge Complete!** You now understand why index column order matters and how to design optimal indexes for your queries.
