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

-- Trigger: Fires ONLY when quantity changes, preserving resources
CREATE OR REPLACE TRIGGER trg_inventory_audit
AFTER UPDATE ON products
FOR EACH ROW
WHEN (OLD.quantity_in_stock IS DISTINCT FROM NEW.quantity_in_stock)
EXECUTE FUNCTION fn_inventory_audit();
