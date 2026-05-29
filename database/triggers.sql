-- ============================================================
-- TRIGGERS
-- ============================================================

-- Trigger Function 1: Log inventory changes to inventory_audit
CREATE OR REPLACE FUNCTION fn_inventory_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_reason VARCHAR(255);
BEGIN
    -- Try to capture a dynamic reason set by backend/procedures
    -- The second parameter 'true' stops Postgres from throwing an error if the setting doesn't exist
    v_reason := current_setting('warehouseflow.audit_reason', true);

    -- Fallback to a default if no specific context was set by the application session
    IF v_reason IS NULL OR v_reason = '' THEN
        v_reason := 'System Stock Adjustment';
    END IF;

    INSERT INTO inventory_audit (
        product_id,
        old_quantity,
        new_quantity,
        changed_at,
        reason
    )
    VALUES (
        NEW.product_id,
        OLD.quantity_in_stock,
        NEW.quantity_in_stock,
        NOW(),
        v_reason
    );

    RETURN NEW;
END;
$$;

-- Fires ONLY when quantity changes, preserving resources
CREATE OR REPLACE TRIGGER trg_inventory_audit
AFTER UPDATE ON products
FOR EACH ROW
WHEN (OLD.quantity_in_stock IS DISTINCT FROM NEW.quantity_in_stock)
EXECUTE FUNCTION fn_inventory_audit();

-- Trigger Function 2: Log price changes to price_audit
CREATE OR REPLACE FUNCTION fn_price_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- No internal IF statement required
    -- The trigger definition guarantees this only runs when a change happens.
    INSERT INTO price_audit (
        product_id,
        old_price,
        new_price,
        changed_at
    )
    VALUES (
        NEW.product_id,
        OLD.price,
        NEW.price,
        NOW()
    );

    RETURN NEW;
END;
$$;

-- Fires ONLY when the price actually changes
CREATE OR REPLACE TRIGGER trg_price_audit
AFTER UPDATE ON products
FOR EACH ROW
WHEN (OLD.price IS DISTINCT FROM NEW.price) -- Intercepts changes early at the database level
EXECUTE FUNCTION fn_price_audit();

-- Trigger Function 3: Block updates that would cause negative inventory
-- Note: probably not needed due to CHECK constraint in products table, but it produces
-- a far more descriptive error message with context about what the attempted change was
CREATE OR REPLACE FUNCTION fn_prevent_negative_inventory()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- No internal IF required due to the trigger's WHEN clause
    RAISE EXCEPTION 
        'Inventory update rejected: product % would go negative. Current: %, Attempted final balance: %, Delta change: %',
        NEW.product_id,
        OLD.quantity_in_stock,
        NEW.quantity_in_stock,
        (NEW.quantity_in_stock - OLD.quantity_in_stock);
END;
$$;

-- ONLY fires if an update tries to break the zero floor
CREATE OR REPLACE TRIGGER trg_prevent_negative_inventory
BEFORE UPDATE ON products
FOR EACH ROW
WHEN (NEW.quantity_in_stock < 0) -- Intercepts the bad data immediately
EXECUTE FUNCTION fn_prevent_negative_inventory();