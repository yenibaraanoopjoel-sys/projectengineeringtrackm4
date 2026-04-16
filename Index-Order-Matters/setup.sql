-- Index Order Matters: PostgreSQL Challenge
-- This script sets up a database to demonstrate how index column order affects query performance

-- Create the database
CREATE DATABASE IF NOT EXISTS index_challenge;

-- Connect to the database
\c index_challenge;

-- Create a users table with relevant columns
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL,
    status VARCHAR(20) NOT NULL,
    country VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP
);

-- Insert sample data for testing
INSERT INTO users (username, email, status, country, created_at, last_login) VALUES
('john_doe', 'john@example.com', 'active', 'USA', '2023-01-15', '2024-01-10'),
('jane_smith', 'jane@example.com', 'active', 'Canada', '2023-02-20', '2024-01-15'),
('bob_wilson', 'bob@example.com', 'inactive', 'USA', '2023-03-10', '2023-11-20'),
('alice_jones', 'alice@example.com', 'active', 'UK', '2023-04-05', '2024-01-18'),
('charlie_brown', 'charlie@example.com', 'active', 'USA', '2023-05-12', '2024-01-12'),
('diana_prince', 'diana@example.com', 'inactive', 'Canada', '2023-06-22', '2023-12-05'),
('edward_norton', 'edward@example.com', 'active', 'USA', '2023-07-18', '2024-01-14'),
('fiona_apple', 'fiona@example.com', 'active', 'UK', '2023-08-30', '2024-01-16'),
('george_mitchell', 'george@example.com', 'inactive', 'Germany', '2023-09-14', '2023-10-22'),
('hannah_montana', 'hannah@example.com', 'active', 'USA', '2023-10-08', '2024-01-17');

-- Generate more sample data to make the performance difference noticeable
INSERT INTO users (username, email, status, country, created_at, last_login)
SELECT 
    'user_' || i,
    'user_' || i || '@example.com',
    CASE WHEN i % 3 = 0 THEN 'inactive' ELSE 'active' END,
    CASE 
        WHEN i % 4 = 0 THEN 'USA'
        WHEN i % 4 = 1 THEN 'Canada'
        WHEN i % 4 = 2 THEN 'UK'
        ELSE 'Germany'
    END,
    CURRENT_TIMESTAMP - INTERVAL '1 day' * (i % 365),
    CURRENT_TIMESTAMP - INTERVAL '1 day' * (i % 30)
FROM generate_series(11, 1000) AS t(i);

-- Create index with INCORRECT column order
-- This index has (country, status) but the query filters on (status, country)
-- Due to the Left-Most Prefix Rule, PostgreSQL cannot efficiently use this index
CREATE INDEX idx_users_incorrect ON users (country, status);

-- Display current table structure
\d users;

-- Show current indexes
\di;

-- Display sample data
SELECT * FROM users LIMIT 5;
