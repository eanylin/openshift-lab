"""FX rate service — Act 2+ (app factory, Flask 3-compatible)."""

from __future__ import annotations

import os
from decimal import Decimal
from importlib import metadata
from pathlib import Path

import requests
from flask import Flask, jsonify, send_from_directory

_UI_DIR = Path(__file__).resolve().parent.parent


# Demo static mid-market-ish rates (Xe.com snapshot 2026-10-01 UTC).
# Not a live feed — values are fixed for reproducible demos/tests.
STATIC_RATES = {
    "usdsgd": Decimal("1.2780"),
    "eurusd": Decimal("1.1325"),
}


def create_app() -> Flask:
    app = Flask(__name__)
    app.config["UPSTREAM_RATES_URL"] = os.environ.get("UPSTREAM_RATES_URL", "")
    app.config["RATES"] = dict(STATIC_RATES)

    @app.route("/", methods=["GET", "HEAD"])
    def index():
        # Minimal demo UI — same file served by Act 0 legacy image.
        return send_from_directory(_UI_DIR, "demo_ui.html")

    @app.get("/healthz")
    def healthz():
        return jsonify(status="ok")

    @app.get("/rate/<pair>")
    def rate(pair: str):
        pair_key = pair.lower()
        upstream = app.config["UPSTREAM_RATES_URL"]
        if upstream:
            try:
                resp = requests.get(
                    f"{upstream.rstrip('/')}/rate/{pair_key}",
                    timeout=2.0,
                )
                if resp.ok:
                    return jsonify(resp.json())
            except requests.RequestException:
                pass
        value = app.config["RATES"].get(pair_key)
        if value is None:
            return jsonify(error="unknown pair"), 404
        # Flask 3 default JSON provider handles Decimal
        return jsonify(pair=pair_key, rate=str(value))

    @app.get("/versions")
    def versions():
        return jsonify(
            {dist.metadata["Name"].lower(): dist.metadata["Version"]
             for dist in sorted(metadata.distributions(),
                                key=lambda d: d.metadata["Name"].lower())
             if dist.metadata["Name"].lower() != "pip"}
        )

    return app


# Gunicorn target: fxrate:app
app = create_app()
