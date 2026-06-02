# WarehouseFlow — Architecture

## Overview

WarehouseFlow is a Dockerized inventory and order management backend built with PostgreSQL and FastAPI. The system follows a database-centric architecture: business rules, transactional integrity, inventory management, and audit logging are implemented in PostgreSQL using stored procedures, functions, and triggers. The FastAPI layer remains intentionally thin, handling request validation, database interaction, and response serialization.

---

## System Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│                        Docker Network                       │
│                                                             │
│   ┌──────────────────┐          ┌──────────────────────┐    │
│   │   FastAPI (api)  │          │ PostgreSQL (postgres)│    │
│   │                  │          │                      │    │
│   │  main.py         │◄────────►│  schema.sql          │    │
│   │  routes/         │ asyncpg  │  procedures.sql      │    │
│   │  models.py       │ pool     │  triggers.sql        │    │
│   │  db.py           │          │  seed.sql            │    │
│   │                  │          │                      │    │
│   │  port 8000       │          │  port 5432           │    │
│   └──────────────────┘          └──────────────────────┘    │
│            ▲                                                │
└────────────┼────────────────────────────────────────────────┘
             │ HTTP
     ┌───────┴────────┐
     │    Client      │
     │ (Swagger UI /  │
     │  curl / app)   │
     └────────────────┘
```

---

# Database Schema

```text
customers
─────────────────────────────
customer_id  PK  IDENTITY
name         VARCHAR(255)
email        VARCHAR(255) UNIQUE
created_at   TIMESTAMPTZ

        │
        │ 1
        ▼ N

orders
─────────────────────────────
order_id      PK  IDENTITY
customer_id   FK → customers
order_date    TIMESTAMPTZ
status        VARCHAR(50)
total_amount  NUMERIC(10,2)

        │
        │ 1
        ▼ N

order_items
─────────────────────────────
order_item_id  PK  IDENTITY
order_id       FK → orders      ON DELETE CASCADE
product_id     FK → products    ON DELETE RESTRICT
quantity       INT CHECK (> 0)
unit_price     NUMERIC(10,2)
UNIQUE(order_id, product_id)


products
─────────────────────────────
product_id         PK  IDENTITY
sku                VARCHAR(50) UNIQUE
name               VARCHAR(255)
price              NUMERIC(10,2)
quantity_in_stock  INT CHECK (>= 0)
created_at         TIMESTAMPTZ

        │
        ├───────────────────────────────┐
        │                               │
        ▼ N                             ▼ N

inventory_audit                  price_audit
─────────────────────────        ─────────────────────────
audit_id      PK SERIAL          audit_id     PK SERIAL
product_id    FK products        product_id   FK products
old_quantity  INT                old_price    NUMERIC(10,2)
new_quantity  INT                new_price    NUMERIC(10,2)
changed_at    TIMESTAMP          changed_at   TIMESTAMP
reason        VARCHAR(255)
```

### Relationships

- One customer can have many orders.
- One order can contain many order items.
- One product can appear in many order items.
- One product can generate many inventory audit records.
- One product can generate many price audit records.

---

# Stored Procedures & Functions

| Name                                                                      | Type      | Description                                                                                                                                                      |
| ------------------------------------------------------------------------- | --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `create_order(p_customer_id INT, p_items_json JSONB, OUT p_order_id INT)` | PROCEDURE | Validates stock, creates order header and line items, decrements inventory, and returns the generated order ID. Executes atomically within a single transaction. |
| `receive_inventory(product_id, quantity, reason)`                         | PROCEDURE | Safely increments inventory levels while maintaining audit history.                                                                                              |
| `get_low_stock_products(threshold)`                                       | FUNCTION  | Returns products at or below a specified stock threshold. Implemented in `LANGUAGE sql` for planner inlining.                                                    |
| `get_monthly_sales(month, year)`                                          | FUNCTION  | Returns monthly product sales totals while excluding cancelled orders. Uses index-friendly date range filtering.                                                 |

### Concurrency Controls

#### Order Creation

`create_order` acquires row-level locks using:

```sql
SELECT ...
FOR UPDATE
```

Products are locked in ascending `product_id` order before stock validation and inventory updates occur.

This provides:

- Consistent inventory allocation under concurrent load
- Protection against overselling
- Deadlock avoidance when multiple orders contain overlapping products

#### Inventory Receipts

`receive_inventory` also uses row-level locking to ensure inventory updates remain safe under concurrent access.

---

# Triggers

| Trigger                          | Table       | Timing | Event                  | Purpose                        |
| -------------------------------- | ----------- | ------ | ---------------------- | ------------------------------ |
| `trg_inventory_audit`            | products    | AFTER  | UPDATE                 | Records inventory changes      |
| `trg_price_audit`                | products    | AFTER  | UPDATE                 | Records price changes          |
| `trg_prevent_negative_inventory` | products    | BEFORE | UPDATE                 | Prevents negative stock values |
| `trg_update_order_total`         | order_items | AFTER  | INSERT, UPDATE, DELETE | Recalculates order totals      |

### Trigger Optimizations

Audit triggers use:

```sql
WHEN (OLD.column IS DISTINCT FROM NEW.column)
```

This prevents PostgreSQL from invoking trigger functions when monitored values have not changed.

### Audit Context

`trg_inventory_audit` reads an optional transaction-scoped context value:

```sql
current_setting('warehouseflow.audit_reason', true)
```

This allows audit records to include business context without requiring additional procedure parameters.

---

# API Layer

The FastAPI service acts as a validation and orchestration layer.

Each endpoint:

1. Validates request payloads using Pydantic v2 models
2. Acquires a connection from the asyncpg pool
3. Executes a stored procedure or function
4. Maps database results into response models
5. Translates database exceptions into structured HTTP responses

### Endpoints

| Method | Path                     | Description                |
| ------ | ------------------------ | -------------------------- |
| GET    | `/products`              | Returns all products       |
| POST   | `/orders`                | Creates an order           |
| POST   | `/inventory/receive`     | Receives inventory         |
| GET    | `/reports/low-stock`     | Returns low-stock products |
| GET    | `/reports/monthly-sales` | Returns monthly sales data |
| GET    | `/health`                | Health probe endpoint      |

### Response Model Transformation

Pydantic v2 `model_validator(mode="before")` hooks are used where appropriate to transform raw database records into API response models while keeping route handlers lightweight.

### Error Handling

Business rule violations raised within PostgreSQL procedures are surfaced through `asyncpg` exceptions and translated into HTTP 400 responses.

---

# Connection Pooling

The database pool is initialized once during FastAPI startup using the application lifespan context manager.

Configuration:

```python
min_size=2
max_size=10
```

Lifecycle:

1. Application startup creates the pool.
2. Requests acquire a connection from the pool.
3. Connections are automatically returned after use.
4. Application shutdown closes the pool gracefully.

This avoids connection creation overhead while ensuring resources are released correctly.

---

# Session Variables

Before inventory adjustments, the API can attach contextual audit information to the current transaction:

```sql
SELECT set_config(
    'warehouseflow.audit_reason',
    $1,
    true
);
```

Passing `true` scopes the setting to the current transaction only. Once the transaction completes, the value is automatically discarded and cannot leak into subsequent requests.

---

# Docker Setup

```text
docker compose up
        │
        ▼
Start PostgreSQL Container
        │
        ▼
Run init.sql
(schema, procedures,
 triggers, seed data)
        │
        ▼
pg_isready Health Check
        │
        ▼
Start FastAPI Container
        │
        ▼
Accept Requests
```

### Services

#### PostgreSQL

- Image: `postgres:16-alpine`
- Persistent volume: `postgres_data`
- Health check: `pg_isready`
- Database initialization via `init.sql`

#### FastAPI

- Base image: `python:3.12-slim`
- Depends on PostgreSQL health status
- Uses Docker internal DNS (`postgres`) for database connectivity

The API container does not start until PostgreSQL reports healthy, preventing startup race conditions.

---

# Key Design Decisions

### Business Logic in the Database

Critical operations such as order creation, stock validation, inventory updates, and audit logging are enforced in PostgreSQL rather than application code. This guarantees consistent behavior regardless of the client interacting with the database.

### Row-Level Locking

Explicit locking ensures inventory correctness under concurrent order placement while avoiding deadlocks through deterministic lock ordering.

### Filter-First Audit Triggers

Trigger `WHEN` clauses prevent unnecessary trigger execution and reduce overhead on high-frequency update operations.

### Index-Friendly Reporting

`get_monthly_sales()` uses:

```sql
order_date >= start_date
AND order_date < end_date
```

instead of:

```sql
EXTRACT(MONTH FROM order_date)
```

allowing PostgreSQL to perform efficient index range scans.

### Historical Price Snapshots

`order_items.unit_price` stores the product price at purchase time rather than referencing the current product price. Historical orders therefore remain financially accurate even after future pricing changes.

---
