"""Run against a local test Compose project. This creates users and restarts its backend.

Example: python scripts/smoke_auth_restart.py -p ev-sharegrid-test
Pass Docker Compose global options (e.g. --env-file, -f) after the script name.
Provide DEMO_{USER,HOST,ADMIN}_PASSWORD via the environment or the hidden prompts.
"""

import json
import os
import secrets
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from getpass import getpass
from uuid import uuid4
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def main():
    compose = ["docker", "compose", *sys.argv[1:]]
    binding = subprocess.check_output([*compose, "port", "backend", "8000"], text=True)
    port = int(binding.splitlines()[0].rsplit(":", 1)[1])
    base = f"http://127.0.0.1:{port}"
    accounts = {}
    for role, email in (("USER", "user1@sharegrid.vn"), ("HOST", "host1@sharegrid.vn"),
                        ("ADMIN", "admin@sharegrid.vn")):
        password = os.getenv(f"DEMO_{role}_PASSWORD") or getpass(f"{email}: ")
        accounts[role] = {"email": email, "password": password}

    def call(route, data=None, token=None, expected=200):
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        req = Request(f"{base}/api/v1/{route}", headers=headers,
                      data=json.dumps(data).encode() if data is not None else None)
        try:
            response = urlopen(req, timeout=12)
        except HTTPError as error:
            response = error
        with response:
            body = json.load(response)
            assert response.status in (expected if isinstance(expected, tuple) else (expected,)), (route, response.status)
            assert "password_hash" not in json.dumps(body)
            return response.status, body

    def check_roles():
        for role, credentials in accounts.items():
            _, session = call("auth/login", credentials)
            token = session["access_token"]
            _, me = call("auth/me", token=token)
            assert session["user"]["role"] == me["role"] == role
            if role == "USER":
                assert me["vehicles"]
            elif role == "HOST":
                _, stations = call("host/stations", token=token)
                assert any(s["ports"] for s in stations["data"])
            else:
                call("admin/clusters", token=token)

    check_roles()
    print("PASS demo login, roles, vehicle, station with ports and admin access")
    payload = {"email": f"qa-{uuid4().hex}@example.test", "password": secrets.token_urlsafe(24),
               "full_name": "Kiểm thử", "role": "ADMIN"}
    # Two simultaneous inserts with differently cased spellings must yield one account.
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda email: call("auth/register", dict(payload, email=email),
                                                   expected=(200, 409)), [payload["email"], payload["email"].upper()]))
    assert sorted(code for code, _ in results) == [200, 409]
    session = next(body for code, body in results if code == 200)
    assert session["user"]["role"] == "USER"
    _, me = call("auth/me", token=session["access_token"])
    assert me["email"] == payload["email"]
    call("auth/register", dict(payload, password="x"), expected=422)
    for credentials in accounts.values():
        call("auth/register", dict(payload, email=credentials["email"].upper()), expected=409)
    print("PASS registration, duplicate race, reserved emails, short password and USER token")
    subprocess.run([*compose, "restart", "backend"], check=True)
    for _ in range(60):
        try:
            with urlopen(base + "/", timeout=2):
                break
        except (OSError, URLError):
            time.sleep(1)
    _, signed_in = call("auth/login", payload)
    assert signed_in["user"] == session["user"]
    check_roles()
    print("PASS persisted account and all three demo logins after backend restart")


if __name__ == "__main__":
    main()
