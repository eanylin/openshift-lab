# LEGACY — do not copy. Act 0/1 application shape (spec FR-002).
# Deliberately uses Flask 2 APIs removed in Flask 3.
# Also includes intentional ExploitIQ "before" sinks removed in Act 2+.

import ssl
from decimal import Decimal
from importlib import metadata
from pathlib import Path

import requests
import urllib3
from flask import Flask, jsonify, request, send_from_directory
from flask.json import JSONEncoder
from jinja2 import BaseLoader, Environment

_UI_DIR = Path(__file__).resolve().parent


class DecimalJSONEncoder(JSONEncoder):
    def default(self, o):
        if isinstance(o, Decimal):
            return str(o)
        return super().default(o)


app = Flask(__name__)
app.json_encoder = DecimalJSONEncoder

_rates: dict[str, Decimal] = {}


@app.before_first_request
def load_rates():
    # Intentionally uses removed Flask 2.3 API for the Act 1/2 narrative.
    _rates.update(
        {
            # Keep Act 0/1 in lockstep with Act 2 demo rates (Xe mid-market ~2026-10-01).
            "usdsgd": Decimal("1.2780"),
            "eurusd": Decimal("1.1325"),
        }
    )


@app.route("/", methods=["GET", "HEAD"])
def index():
    # Minimal demo UI — shows the service is alive (same page as Act 2+).
    return send_from_directory(_UI_DIR, "demo_ui.html")


@app.get("/healthz")
def healthz():
    return jsonify(status="ok")


@app.get("/rate/<pair>")
def rate(pair: str):
    pair_key = pair.lower()
    value = _rates.get(pair_key)
    if value is None:
        return jsonify(error="unknown pair"), 404
    return jsonify(pair=pair_key, rate=value)


@app.get("/fetch")
def fetch():
    """DEMO ONLY — intentional vulnerable sink for ExploitIQ Act 0 (Option B).

    CVE-2024-35195 (requests < 2.32.0): first Session request with
    ``verify=False`` sticks on the urllib3 connection pool.

    Call ``session.send(..., verify=False)`` (intel-listed API around
    ``_get_connection``). Plain ``session.get(verify=False)`` alone often
    lands as ``code_not_reachable`` in Call Chain Analyzer.
    """
    url = (request.args.get("url") or "").strip()
    if not url:
        return jsonify(error="url query parameter required"), 400
    try:
        session = requests.Session()
        session.verify = False
        # 1) Poison the pool (CVE sticky verify=False).
        prepared = session.prepare_request(requests.Request("GET", url))
        session.send(prepared, verify=False, timeout=2.0)
        # 2) Same-host follow-up still verify=False so CCA keeps the sink
        #    grounded on send(..., verify=False) — do NOT flip to verify=True
        #    here; that has returned code_not_reachable in ExploitIQ.
        follow = session.prepare_request(requests.Request("GET", url))
        resp = session.send(follow, verify=False, timeout=2.0)
    except requests.RequestException as exc:
        return jsonify(error=str(exc)), 502
    return jsonify(
        status_code=resp.status_code,
        length=len(resp.content),
        preview=resp.text[:120],
    )


@app.get("/proxy-fetch")
def proxy_fetch():
    """DEMO ONLY — vulnerable urllib3 proxy TLS sink (CVE-2026-97687).

    Uses ProxyManager with proxy_ssl_context set to CERT_NONE and
    cert_reqs='CERT_NONE', exercising the exact TLS-override code path
    that CVE-2026-97687 exploits: target-server settings bleed into the
    proxy connection because proxy_ssl_context / verify_mode are
    incorrectly shared.
    """
    url = (request.args.get("url") or "").strip()
    proxy = request.args.get("proxy", "https://proxy.internal:8080")
    if not url:
        return jsonify(error="url query parameter required"), 400
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    http = urllib3.ProxyManager(
        proxy,
        proxy_ssl_context=ctx,
        cert_reqs="CERT_NONE",
    )
    try:
        resp = http.request("GET", url, timeout=2.0)
    except Exception as exc:
        return jsonify(error=str(exc)), 502
    return jsonify(status=resp.status, length=len(resp.data))


@app.get("/render")
def render_custom():
    """DEMO ONLY — vulnerable Jinja2 template sink (CVE-2026-97689).

    Attacker controls both the template content AND the filename —
    the exact conditions CVE-2026-97689 requires for arbitrary code
    execution via the Jinja compiler, regardless of sandbox.
    """
    template_content = request.args.get("template", "{{ greeting }}")
    filename = request.args.get("filename", "user_template.html")
    env = Environment(loader=BaseLoader())
    tmpl = env.from_string(template_content)
    tmpl.filename = filename
    return tmpl.render(greeting="Hello from FX Rate")


@app.get("/versions")
def versions():
    pkgs = ("flask", "werkzeug", "requests", "urllib3")
    return jsonify({name: metadata.version(name) for name in pkgs})
