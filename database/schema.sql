-- ============================================================
-- WAREHOUSEFLOW SCHEMA
-- ============================================================

-- Products: the core catalog of items in the warehouse
CREATE TABLE products (
    product_id       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku              VARCHAR(50)    NOT NULL UNIQUE,
    name             VARCHAR(255)   NOT NULL,
    price            NUMERIC(10,2)  NOT NULL CHECK (price >= 0),
    quantity_in_stock INT            NOT NULL DEFAULT 0 CHECK (quantity_in_stock >= 0),
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

-- Customers: people or companies placing orders
CREATE TABLE customers (
    customer_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          VARCHAR(255)   NOT NULL,
    email         VARCHAR(255)   NOT NULL UNIQUE,
    created_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

-- Orders: the header record for each customer order
CREATE TABLE orders (
    order_id      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id   INT            NOT NULL REFERENCES customers(customer_id) ON DELETE RESTRICT,
    order_date    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    status        VARCHAR(50)    NOT NULL DEFAULT 'pending' 
        CHECK (status IN ('pending', 'processing', 'shipped', 'delivered', 'cancelled')),
    total_amount  NUMERIC(10,2)  NOT NULL DEFAULT 0.00 CHECK (total_amount >= 0)
);