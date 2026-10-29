"""Contract and smoke tests for fx-rate-service (spec FR-001..004, AC-2.4)."""

from decimal import Decimal

import pytest

from fxrate import STATIC_RATES, create_app


@pytest.fixture()
def client():
    app = create_app()
    app.config["TESTING"] = True
    return app.test_client()


def test_import_app():
    assert create_app() is not None


def test_healthz(client):
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.get_json()["status"] == "ok"


def test_demo_ui(client):
    r = client.get("/")
    assert r.status_code == 200
    assert "text/html" in r.content_type
    body = r.data.decode()
    assert "FX" in body
    assert "/versions" in body
    assert "Convert" in body


def test_rate_usdsgd_contract(client):
    r = client.get("/rate/usdsgd")
    assert r.status_code == 200
    body = r.get_json()
    expected = {"pair": "usdsgd", "rate": str(STATIC_RATES["usdsgd"])}
    assert body == expected
    # Contract: Act N and Act 0 share the same static rate string (spec FR-003 / AC-2.4)
    assert body["rate"] == "1.2780"


def test_rate_unknown(client):
    r = client.get("/rate/xxxyyy")
    assert r.status_code == 404


def test_versions_keys(client):
    r = client.get("/versions")
    assert r.status_code == 200
    data = r.get_json()
    for key in ("flask", "werkzeug", "requests", "urllib3"):
        assert key in data
        assert isinstance(data[key], str) and data[key]
