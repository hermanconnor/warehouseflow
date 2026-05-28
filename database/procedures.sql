-- ============================================================
-- STORED PROCEDURES
-- ============================================================

CREATE OR REPLACE PROCEDURE create_order(
    p_customer_id   INT,
    p_items_json    JSONB,
    OUT p_order_id  INT 
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_total         NUMERIC(10,2) := 0;
    v_item          RECORD;
    v_price         NUMERIC(10,2);
    v_stock         INT;
BEGIN
    -- 1. Validate that the customer exists
    IF NOT EXISTS (SELECT 1 FROM customers WHERE customer_id = p_customer_id) THEN
        RAISE EXCEPTION 'Customer % does not exist', p_customer_id;
    END IF;

    -- 2. Validate JSON structure & content length
    IF p_items_json IS NULL OR JSONB_ARRAY_LENGTH(p_items_json) = 0 THEN
        RAISE EXCEPTION 'Order must contain at least one item';
    END IF;

    -- 3. Create the order header first
    INSERT INTO orders (customer_id, status, total_amount)
    VALUES (p_customer_id, 'pending', 0)
    RETURNING order_id INTO p_order_id;

    -- 4. Unnest, sanitize, and SORT items by product_id to prevent deadlocks
    FOR v_item IN 
        SELECT 
            (elem->>'product_id')::INT AS product_id,
            (elem->>'quantity')::INT AS quantity
        FROM JSONB_ARRAY_ELEMENTS(p_items_json) AS elem
        ORDER BY 1 -- Sorts by product_id ascending
    LOOP
        -- Sanity check on quantities coming from the payload
        IF v_item.quantity <= 0 THEN
            RAISE EXCEPTION 'Invalid quantity % for product %. Must be greater than 0.', 
                v_item.quantity, v_item.product_id;
        END IF;

        -- 5. Lock the row deterministically and extract price/stock
        SELECT price, quantity_in_stock
        INTO v_price, v_stock
        FROM products
        WHERE product_id = v_item.product_id
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product % does not exist', v_item.product_id;
        END IF;

        -- 6. Check stock availability
        IF v_stock < v_item.quantity THEN
            RAISE EXCEPTION 'Insufficient stock for product %. Requested: %, Available: %',
                v_item.product_id, v_item.quantity, v_stock;
        END IF;

        -- 7. Insert line item 
        INSERT INTO order_items (order_id, product_id, quantity, unit_price)
        VALUES (p_order_id, v_item.product_id, v_item.quantity, v_price);

        -- 8. Update inventory balance
        UPDATE products
        SET quantity_in_stock = quantity_in_stock - v_item.quantity
        WHERE product_id = v_item.product_id;

        -- Accumulate total price
        v_total := v_total + (v_price * v_item.quantity);
    END LOOP;

    -- 9. Update header record with final calculated total
    UPDATE orders
    SET total_amount = v_total
    WHERE order_id = p_order_id;

END;
$$;

CREATE OR REPLACE PROCEDURE receive_inventory(
    p_product_id    INT,
    p_quantity      INT,
    p_reason        VARCHAR(255) DEFAULT 'Supplier Shipment'
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- 1. Input Sanitization
    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'Quantity to receive must be greater than zero. Found: %', p_quantity;
    END IF;

    -- 2. Concurrently lock the row and verify existence 
    -- Using FOR UPDATE here prevents a race condition if an order is trying to deduct stock at the same exact millisecond.
    IF NOT EXISTS (SELECT 1 FROM products WHERE product_id = p_product_id FOR UPDATE) THEN
        RAISE EXCEPTION 'Product % does not exist', p_product_id;
    END IF;

    -- 3. Execute the stock adjustment
    UPDATE products
    SET quantity_in_stock = quantity_in_stock + p_quantity
    WHERE product_id = p_product_id;

END;
$$;