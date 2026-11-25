import json

import pytest
from fastapi.testclient import TestClient

from app.config import conninfo_from_env, password_from_secret
from app.main import create_app
from app.repository import InMemoryRepository, load_seed


@pytest.fixture
def client():
    with TestClient(create_app(InMemoryRepository())) as c:
        yield c


def test_health_does_not_need_the_database(client):
    assert client.get("/api/health").json() == {"status": "ok"}


def test_ready_reports_database_state():
    class Down(InMemoryRepository):
        def ping(self):
            return False

    with TestClient(create_app(Down())) as c:
        assert c.get("/api/ready").status_code == 503
    with TestClient(create_app(InMemoryRepository())) as c:
        assert c.get("/api/ready").status_code == 200


def test_lists_all_seed_products(client):
    body = client.get("/api/products").json()
    assert len(body) == len(load_seed())
    assert {"id", "sku", "name", "price_cents", "stock", "category", "image"} <= body[0].keys()


def test_filters_by_category(client):
    body = client.get("/api/products", params={"category": "Tech"}).json()
    assert body and all(p["category"] == "Tech" for p in body)


def test_keyword_search_matches_name_or_description_case_insensitively(client):
    names = [p["name"] for p in client.get("/api/products", params={"q": "COFFEE"}).json()]
    assert names == ["Pour-over coffee set"]
    # "USB-C" appears only in descriptions
    assert len(client.get("/api/products", params={"q": "usb-c"}).json()) >= 2


def test_limit_is_bounded(client):
    assert len(client.get("/api/products", params={"limit": 3}).json()) == 3
    assert client.get("/api/products", params={"limit": 0}).status_code == 422
    assert client.get("/api/products", params={"limit": 1000}).status_code == 422


def test_get_product_and_404(client):
    assert client.get("/api/products/1").json()["sku"] == "KIT-001"
    assert client.get("/api/products/9999").status_code == 404


def test_categories_are_sorted_and_unique(client):
    assert client.get("/api/categories").json() == ["Home", "Kitchen", "Outdoors", "Tech"]


def test_info_names_the_pod(client):
    assert client.get("/api/info").json()["service"] == "catalog"


def test_password_comes_from_the_rds_managed_secret():
    secret = json.dumps({"username": "shoplane_admin", "password": "p@ss word"})
    assert password_from_secret(secret) == ("shoplane_admin", "p@ss word")

    calls = []

    def fake_fetch(arn, region):
        calls.append((arn, region))
        return secret

    info = conninfo_from_env(
        {"DB_HOST": "db.internal", "DB_SECRET_ARN": "arn:aws:secretsmanager:x", "AWS_REGION": "us-east-1"},
        fetch=fake_fetch,
    )
    assert calls == [("arn:aws:secretsmanager:x", "us-east-1")]
    assert "host=db.internal" in info and "sslmode=require" in info and "user=shoplane_admin" in info


def test_local_password_from_env_without_secrets_manager():
    info = conninfo_from_env({"DB_HOST": "localhost", "DB_USER": "u", "DB_PASSWORD": "p", "DB_SSLMODE": "disable"})
    assert "sslmode=disable" in info and "user=u" in info
