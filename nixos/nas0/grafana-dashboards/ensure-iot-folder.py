"""Rename the existing provisioned folder in place, retaining its UID and ACLs."""

import argparse
import base64
import http.client
import json
import shlex
import socket
import time
from pathlib import Path


class UnixConnection(http.client.HTTPConnection):
    def __init__(self, path):
        super().__init__("localhost", timeout=10)
        self.path = path

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(self.path)


def ensure_folder(request, uid):
    status, data = request("GET", f"/api/folders/{uid}")
    if status != 200:
        raise RuntimeError(f"Folder lookup failed (HTTP {status})")
    if data["title"] == "IOT":
        return
    if data["title"] != "Qingping":
        raise RuntimeError("Refusing to rename an unexpected folder")
    status, data = request("PUT", f"/api/folders/{uid}", {"title": "IOT", "overwrite": True})
    if status != 200 or data.get("title") != "IOT" or data.get("uid") != uid:
        raise RuntimeError(f"Folder rename failed (HTTP {status})")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--credential", required=True)
    parser.add_argument("--socket", required=True)
    parser.add_argument("--uid", required=True)
    args = parser.parse_args()
    values = {}
    for line in Path(args.credential).read_text().splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = shlex.split(value)[0] if shlex.split(value) else ""
    # This deployment uses the existing Grafana account's password for its
    # Prometheus Basic Auth as well; never place it in argv, source or logs.
    password = values["ENV_BASIC_AUTH_TOKEN"]
    auth = base64.b64encode(f"kasei:{password}".encode()).decode()

    def request(method, path, body=None):
        conn = UnixConnection(args.socket)
        try:
            conn.request(method, path, body=None if body is None else json.dumps(body),
                         headers={"Authorization": f"Basic {auth}", "Content-Type": "application/json"})
            response = conn.getresponse()
            return response.status, json.loads(response.read())
        finally:
            conn.close()

    for attempt in range(60):
        try:
            ensure_folder(request, args.uid)
            print("IOT folder ready; existing UID retained")
            return
        except Exception as exc:
            if attempt == 59:
                # Exception types only: HTTP responses or credentials stay private.
                raise SystemExit(f"IOT folder migration failed ({type(exc).__name__})") from None
            time.sleep(1)


if __name__ == "__main__":
    main()
