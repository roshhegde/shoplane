"""Where products come from.

The API only talks to the Repository interface, so tests use an in-memory
version and production uses Postgres. That keeps the tests fast and lets them
run in CI without a database.
"""

import json
from pathlib import Path
from typing import Protocol

from .models import Product

SEED_FILE = Path(__file__).parent / "seed_products.json"


def load_seed() -> list[dict]:
    return json.loads(SEED_FILE.read_text())


class Repository(Protocol):
    def list_products(self, q: str | None, category: str | None, limit: int) -> list[Product]: ...
    def get_product(self, product_id: int) -> Product | None: ...
    def list_categories(self) -> list[str]: ...
    def ping(self) -> bool: ...
    def close(self) -> None: ...


class InMemoryRepository:
    """Seed data held in a list. Used by tests and by `CATALOG_BACKEND=memory`."""

    def __init__(self, rows: list[dict] | None = None):
        rows = rows if rows is not None else load_seed()
        self._products = [Product(id=i + 1, **row) for i, row in enumerate(rows)]

    def list_products(self, q: str | None, category: str | None, limit: int) -> list[Product]:
        items = self._products
        if category:
            items = [p for p in items if p.category == category]
        if q:
            needle = q.lower()
            items = [p for p in items if needle in p.name.lower() or needle in p.description.lower()]
        return items[:limit]

    def get_product(self, product_id: int) -> Product | None:
        return next((p for p in self._products if p.id == product_id), None)

    def list_categories(self) -> list[str]:
        return sorted({p.category for p in self._products})

    def ping(self) -> bool:
        return True

    def close(self) -> None:
        pass


SCHEMA = """
CREATE TABLE IF NOT EXISTS products (
    id          SERIAL PRIMARY KEY,
    sku         TEXT UNIQUE NOT NULL,
    name        TEXT NOT NULL,
    description TEXT NOT NULL,
    category    TEXT NOT NULL,
    price_cents INTEGER NOT NULL CHECK (price_cents >= 0),
    stock       INTEGER NOT NULL CHECK (stock >= 0),
    image       TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS products_category_idx ON products (category);
"""

COLUMNS = "id, sku, name, description, category, price_cents, stock, image"


class PostgresRepository:
    """Products in RDS PostgreSQL, through a small connection pool."""

    def __init__(self, conninfo: str):
        from psycopg.rows import dict_row
        from psycopg_pool import ConnectionPool

        self._pool = ConnectionPool(
            conninfo,
            min_size=1,
            max_size=5,
            kwargs={"row_factory": dict_row},
            open=True,
        )

    def migrate_and_seed(self) -> None:
        """Create the table and load seed products if it's empty.

        Every lab starts from a fresh database, so the service seeds itself.
        Two pods may start at once; an advisory lock makes only one of them do it.
        """
        with self._pool.connection() as conn:
            conn.execute("SELECT pg_advisory_lock(42)")
            try:
                conn.execute(SCHEMA)
                count = conn.execute("SELECT count(*) AS n FROM products").fetchone()["n"]
                if count == 0:
                    with conn.cursor() as cur:
                        cur.executemany(
                            "INSERT INTO products (sku, name, description, category, price_cents, stock, image) "
                            "VALUES (%(sku)s, %(name)s, %(description)s, %(category)s, %(price_cents)s, %(stock)s, %(image)s)",
                            load_seed(),
                        )
                conn.commit()
            finally:
                conn.execute("SELECT pg_advisory_unlock(42)")

    def list_products(self, q: str | None, category: str | None, limit: int) -> list[Product]:
        sql = f"SELECT {COLUMNS} FROM products WHERE true"
        params: list = []
        if category:
            sql += " AND category = %s"
            params.append(category)
        if q:
            # Keyword search for now. Phase 6 adds semantic search on Google Cloud
            # and keeps this query as the fallback.
            sql += " AND (name ILIKE %s OR description ILIKE %s)"
            params += [f"%{q}%", f"%{q}%"]
        sql += " ORDER BY id LIMIT %s"
        params.append(limit)
        with self._pool.connection() as conn:
            return [Product(**row) for row in conn.execute(sql, params).fetchall()]

    def get_product(self, product_id: int) -> Product | None:
        with self._pool.connection() as conn:
            row = conn.execute(f"SELECT {COLUMNS} FROM products WHERE id = %s", [product_id]).fetchone()
        return Product(**row) if row else None

    def list_categories(self) -> list[str]:
        with self._pool.connection() as conn:
            rows = conn.execute("SELECT DISTINCT category FROM products ORDER BY category").fetchall()
        return [r["category"] for r in rows]

    def ping(self) -> bool:
        try:
            with self._pool.connection(timeout=2) as conn:
                conn.execute("SELECT 1")
            return True
        except Exception:
            return False

    def close(self) -> None:
        self._pool.close()
