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

-- Order Items: individual line items belonging to an order
CREATE TABLE order_items (
    order_item_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id      INT            NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    product_id    INT            NOT NULL REFERENCES products(product_id) ON DELETE RESTRICT,
    quantity      INT            NOT NULL CHECK (quantity > 0),
    unit_price    NUMERIC(10,2)  NOT NULL CHECK (unit_price >= 0),

    -- Prevents the same product from being added as two separate rows in the same order
    CONSTRAINT unique_order_product UNIQUE (order_id, product_id)
);

-- Inventory Audit: automatic log of every stock level change
CREATE TABLE inventory_audit (
    audit_id      SERIAL PRIMARY KEY,
    product_id    INT            NOT NULL REFERENCES products(product_id) ON UPDATE CASCADE ON DELETE CASCADE,
    old_quantity  INT            NOT NULL,
    new_quantity  INT            NOT NULL,
    changed_at    TIMESTAMP      NOT NULL DEFAULT NOW(),
    reason        VARCHAR(255)
);

-- Price Audit: automatic log of every price change
CREATE TABLE price_audit (
    audit_id      SERIAL PRIMARY KEY,
    product_id    INT            NOT NULL REFERENCES products(product_id),
    old_price     NUMERIC(10,2)  NOT NULL,
    new_price     NUMERIC(10,2)  NOT NULL,
    changed_at    TIMESTAMP      NOT NULL DEFAULT NOW()
);