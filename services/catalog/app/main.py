"""Shoplane catalog service.

Runs as pods on EKS behind the ALB. CloudFront sends every /api/* request here.
"""

import logging
import os
import socket
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Query, Request
from fastapi.responses import JSONResponse

from .models import Product
from .repository import InMemoryRepository, Repository

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("catalog")


def build_repository() -> Repository:
    if os.environ.get("CATALOG_BACKEND", "postgres") == "memory":
        log.info("using in-memory catalog")
        return InMemoryRepository()

    from .config import conninfo_from_env
    from .repository import PostgresRepository

    repo = PostgresRepository(conninfo_from_env())
    repo.migrate_and_seed()
    log.info("connected to postgres and ensured schema and seed data")
    return repo


def create_app(repository: Repository | None = None) -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.repo = repository or build_repository()
        yield
        # Kubernetes sends SIGTERM before stopping a pod; close connections cleanly.
        app.state.repo.close()

    app = FastAPI(title="Shoplane catalog", version="0.2.0", lifespan=lifespan, docs_url="/api/docs", openapi_url="/api/openapi.json")

    def repo(request: Request) -> Repository:
        return request.app.state.repo

    @app.get("/api/health")
    def health():
        """Liveness: the process is up. Never touches the database, so a slow
        database doesn't make Kubernetes restart healthy pods."""
        return {"status": "ok"}

    @app.get("/api/ready")
    def ready(r: Repository = Depends(repo)):
        """Readiness: only send traffic here if the database answers."""
        if not r.ping():
            return JSONResponse({"status": "database unavailable"}, status_code=503)
        return {"status": "ready"}

    @app.get("/api/info")
    def info():
        """Which pod answered. Refresh the storefront to watch the ALB spread requests."""
        return {
            "service": "catalog",
            "version": app.version,
            "pod": socket.gethostname(),
            "node": os.environ.get("NODE_NAME", "local"),
        }

    @app.get("/api/products", response_model=list[Product])
    def list_products(
        q: str | None = Query(None, max_length=100, description="Keyword to look for in name or description"),
        category: str | None = Query(None, max_length=50),
        limit: int = Query(50, ge=1, le=100),
        r: Repository = Depends(repo),
    ):
        return r.list_products(q=q, category=category, limit=limit)

    @app.get("/api/products/{product_id}", response_model=Product)
    def get_product(product_id: int, r: Repository = Depends(repo)):
        product = r.get_product(product_id)
        if product is None:
            raise HTTPException(status_code=404, detail="Product not found")
        return product

    @app.get("/api/categories", response_model=list[str])
    def list_categories(r: Repository = Depends(repo)):
        return r.list_categories()

    return app


app = create_app()
