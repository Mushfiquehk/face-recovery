"""WHOOP OAuth and data pull (API v2).

WHOOP Recovery is ground truth for the research strand only; it never feeds a Recovery Score
(CONTEXT.md). Raw responses are saved verbatim so pairing can be re-run without re-fetching.
"""

from __future__ import annotations

import json
import secrets
import time
import webbrowser
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlparse

import requests

from face_pipeline.config import Config

SCOPES = "offline read:recovery read:sleep read:cycles read:profile"
PAGE_LIMIT = 25  # API maximum


def _token_path(cfg: Config) -> Path:
    return cfg.whoop_data_dir / "tokens.json"


def _save_tokens(cfg: Config, payload: dict) -> dict:
    tokens = {
        "access_token": payload["access_token"],
        # WHOOP rotates the refresh token on every refresh; keep the old one if none came back.
        "refresh_token": payload.get("refresh_token") or _load_tokens(cfg).get("refresh_token"),
        "expires_at": time.time() + int(payload.get("expires_in", 3600)) - 60,
        "scope": payload.get("scope"),
    }
    path = _token_path(cfg)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(tokens, indent=2))
    path.chmod(0o600)
    return tokens


def _load_tokens(cfg: Config) -> dict:
    path = _token_path(cfg)
    return json.loads(path.read_text()) if path.exists() else {}


def authorize(cfg: Config) -> None:
    """Runs the authorization-code flow once, catching the redirect on a local server."""
    cfg.require("whoop_client_id", "whoop_client_secret")
    redirect = urlparse(cfg.whoop_redirect_uri)
    state = secrets.token_urlsafe(16)
    url = f"{cfg.whoop_api_base_url}/oauth/oauth2/auth?" + urlencode({
        "response_type": "code",
        "client_id": cfg.whoop_client_id,
        "redirect_uri": cfg.whoop_redirect_uri,
        "scope": SCOPES,
        "state": state,
    })

    result: dict[str, str] = {}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802 (http.server naming)
            parsed = urlparse(self.path)
            if parsed.path != redirect.path:
                self.send_response(404)
                self.end_headers()
                return
            query = {k: v[0] for k, v in parse_qs(parsed.query).items()}
            result.update(query)
            ok = "code" in query and query.get("state") == state
            self.send_response(200 if ok else 400)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(
                b"WHOOP connected. You can close this tab." if ok
                else b"WHOOP authorization failed. Check the terminal."
            )

        def log_message(self, *args):
            pass

    server = HTTPServer((redirect.hostname or "localhost", redirect.port or 80), Handler)
    print(f"Opening WHOOP login. If no browser opens, visit:\n{url}\n")
    webbrowser.open(url)
    while not result:
        server.handle_request()
    server.server_close()

    if result.get("state") != state:
        raise SystemExit("OAuth state mismatch; aborting.")
    if "code" not in result:
        raise SystemExit(f"WHOOP returned an error: {result}")

    response = requests.post(f"{cfg.whoop_api_base_url}/oauth/oauth2/token", data={
        "grant_type": "authorization_code",
        "code": result["code"],
        "client_id": cfg.whoop_client_id,
        "client_secret": cfg.whoop_client_secret,
        "redirect_uri": cfg.whoop_redirect_uri,
    }, timeout=30)
    response.raise_for_status()
    _save_tokens(cfg, response.json())
    print(f"Tokens saved to {_token_path(cfg)}")


def _access_token(cfg: Config) -> str:
    tokens = _load_tokens(cfg)
    if not tokens:
        raise SystemExit("Not connected to WHOOP. Run: face-pipeline whoop-auth")
    if time.time() < tokens["expires_at"]:
        return tokens["access_token"]
    if not tokens.get("refresh_token"):
        raise SystemExit("WHOOP token expired and no refresh token. Run: face-pipeline whoop-auth")
    response = requests.post(f"{cfg.whoop_api_base_url}/oauth/oauth2/token", data={
        "grant_type": "refresh_token",
        "refresh_token": tokens["refresh_token"],
        "client_id": cfg.whoop_client_id,
        "client_secret": cfg.whoop_client_secret,
        "scope": "offline",
    }, timeout=30)
    if response.status_code in (400, 401):
        raise SystemExit("WHOOP refresh rejected. Run: face-pipeline whoop-auth")
    response.raise_for_status()
    return _save_tokens(cfg, response.json())["access_token"]


def fetch_collection(cfg: Config, path: str, start: datetime, end: datetime,
                     session: requests.Session | None = None) -> list[dict]:
    """Follows `next_token` until the collection is exhausted."""
    session = session or requests.Session()
    headers = {"Authorization": f"Bearer {_access_token(cfg)}"}
    params: dict[str, str | int] = {
        "start": _iso(start), "end": _iso(end), "limit": PAGE_LIMIT,
    }
    records: list[dict] = []
    while True:
        response = session.get(f"{cfg.whoop_api_base_url}/developer{path}",
                               headers=headers, params=params, timeout=30)
        if response.status_code == 429:
            time.sleep(int(response.headers.get("Retry-After", "5")))
            continue
        response.raise_for_status()
        body = response.json()
        records.extend(body.get("records", []))
        next_token = body.get("next_token")
        if not next_token:
            return records
        params["nextToken"] = next_token


def pull(cfg: Config, start: datetime, end: datetime) -> dict[str, int]:
    """Saves recoveries and sleeps for [start, end) as raw JSON; returns record counts."""
    cfg.require("whoop_client_id", "whoop_client_secret")
    cfg.whoop_data_dir.mkdir(parents=True, exist_ok=True)
    counts = {}
    for name, path in (("recovery", "/v2/recovery"), ("sleep", "/v2/activity/sleep")):
        records = fetch_collection(cfg, path, start, end)
        (cfg.whoop_data_dir / f"{name}.json").write_text(json.dumps({
            "pulled_at": _iso(datetime.now(timezone.utc)),
            "start": _iso(start),
            "end": _iso(end),
            "records": records,
        }, indent=2))
        counts[name] = len(records)
    return counts


def load_pulled(cfg: Config) -> tuple[list[dict], list[dict]]:
    """Returns (recoveries, sleeps) from the last pull."""
    out = []
    for name in ("recovery", "sleep"):
        path = cfg.whoop_data_dir / f"{name}.json"
        if not path.exists():
            raise SystemExit(f"No {path}. Run: face-pipeline whoop-pull")
        out.append(json.loads(path.read_text())["records"])
    return out[0], out[1]


def _iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
