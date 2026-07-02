import os
import time
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, status
from pydantic import BaseModel, Field
from psycopg import OperationalError
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool


def env(name: str, default: str | None = None) -> str:
    value = os.getenv(name, default)
    if value is None or value == "":
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def database_settings() -> dict[str, str | int]:
    return {
        "host": env("DB_HOST"),
        "port": int(env("DB_PORT", "5432")),
        "dbname": env("DB_NAME"),
        "user": env("DB_USER"),
        "password": env("DB_PASSWORD"),
    }


pool: ConnectionPool | None = None


def get_pool() -> ConnectionPool:
    if pool is None:
        raise RuntimeError("Database pool is not initialized")
    return pool


def wait_for_database(db_pool: ConnectionPool) -> None:
    attempts = int(os.getenv("DB_CONNECT_ATTEMPTS", "30"))
    delay_seconds = float(os.getenv("DB_CONNECT_DELAY_SECONDS", "2"))

    for attempt in range(1, attempts + 1):
        try:
            with db_pool.connection() as conn:
                conn.execute("SELECT 1")
            return
        except OperationalError:
            if attempt == attempts:
                raise
            time.sleep(delay_seconds)


def initialize_schema(db_pool: ConnectionPool) -> None:
    with db_pool.connection() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS items (
                id SERIAL PRIMARY KEY,
                name VARCHAR(120) NOT NULL,
                description TEXT,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
            """
        )


@asynccontextmanager
async def lifespan(app: FastAPI):
    global pool

    pool = ConnectionPool(
        conninfo="",
        min_size=1,
        max_size=int(os.getenv("DB_POOL_MAX", "5")),
        kwargs={**database_settings(), "row_factory": dict_row},
        open=False,
    )
    pool.open()
    wait_for_database(pool)
    initialize_schema(pool)

    yield

    pool.close()
    pool = None


app = FastAPI(
    title="Inventory CRUD API",
    version="1.0.0",
    lifespan=lifespan,
)


class ItemCreate(BaseModel):
    name: Annotated[str, Field(min_length=1, max_length=120)]
    description: Annotated[str | None, Field(max_length=500)] = None


class ItemUpdate(BaseModel):
    name: Annotated[str | None, Field(min_length=1, max_length=120)] = None
    description: Annotated[str | None, Field(max_length=500)] = None


class Item(BaseModel):
    id: int
    name: str
    description: str | None
    created_at: datetime
    updated_at: datetime


DbPool = Annotated[ConnectionPool, Depends(get_pool)]


@app.get("/")
def root() -> dict[str, str]:
    return {"service": "inventory-api", "status": "running"}


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/readyz")
def readyz(db_pool: DbPool) -> dict[str, str]:
    with db_pool.connection() as conn:
        conn.execute("SELECT 1")
    return {"status": "ready"}


@app.post("/items", response_model=Item, status_code=status.HTTP_201_CREATED)
def create_item(payload: ItemCreate, db_pool: DbPool) -> dict:
    with db_pool.connection() as conn:
        row = conn.execute(
            """
            INSERT INTO items (name, description)
            VALUES (%s, %s)
            RETURNING id, name, description, created_at, updated_at
            """,
            (payload.name, payload.description),
        ).fetchone()
    return row


@app.get("/items", response_model=list[Item])
def list_items(db_pool: DbPool) -> list[dict]:
    with db_pool.connection() as conn:
        rows = conn.execute(
            """
            SELECT id, name, description, created_at, updated_at
            FROM items
            ORDER BY id
            """
        ).fetchall()
    return rows


@app.get("/items/{item_id}", response_model=Item)
def get_item(item_id: int, db_pool: DbPool) -> dict:
    with db_pool.connection() as conn:
        row = conn.execute(
            """
            SELECT id, name, description, created_at, updated_at
            FROM items
            WHERE id = %s
            """,
            (item_id,),
        ).fetchone()

    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Item not found")
    return row


@app.put("/items/{item_id}", response_model=Item)
def update_item(item_id: int, payload: ItemUpdate, db_pool: DbPool) -> dict:
    updates: list[str] = []
    values: list[str | int | None] = []
    fields_set = getattr(payload, "model_fields_set", getattr(payload, "__fields_set__", set()))

    if "name" in fields_set:
        if payload.name is None:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Name cannot be null")
        updates.append("name = %s")
        values.append(payload.name)

    if "description" in fields_set:
        updates.append("description = %s")
        values.append(payload.description)

    if not updates:
        return get_item(item_id, db_pool)

    values.append(item_id)

    with db_pool.connection() as conn:
        row = conn.execute(
            f"""
            UPDATE items
            SET {", ".join(updates)}, updated_at = NOW()
            WHERE id = %s
            RETURNING id, name, description, created_at, updated_at
            """,
            values,
        ).fetchone()

    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Item not found")
    return row


@app.delete("/items/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_item(item_id: int, db_pool: DbPool) -> None:
    with db_pool.connection() as conn:
        result = conn.execute("DELETE FROM items WHERE id = %s", (item_id,))

    if result.rowcount == 0:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Item not found")
