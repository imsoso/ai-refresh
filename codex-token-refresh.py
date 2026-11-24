#!/usr/bin/env python3
import base64, json, os, sys, urllib.request, urllib.parse
from datetime import datetime, timezone, timedelta

AUTH_PATH = os.path.expanduser("~/.codex/auth.json")
CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"

def is_token_expiring_soon(hours=4):
    try:
        with open(AUTH_PATH) as f:
            auth = json.load(f)
        payload = auth["tokens"]["access_token"].split(".")[1]
        payload += "=" * (4 - len(payload) % 4)
        data = json.loads(base64.b64decode(payload))
        exp = datetime.fromtimestamp(data["exp"], tz=timezone.utc)
        return datetime.now(timezone.utc) > exp - timedelta(hours=hours)
    except Exception:
        return True

def main():
    if not is_token_expiring_soon():
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Codex token still valid, skip refresh")
        return

    with open(AUTH_PATH) as f:
        auth = json.load(f)

    refresh_token = auth["tokens"].get("refresh_token")
    if not refresh_token:
        print("No refresh_token found", file=sys.stderr)
        sys.exit(1)

    data = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
        "client_id": CLIENT_ID,
    }).encode()

    req = urllib.request.Request(
        "https://auth.openai.com/oauth/token",
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"}
    )

    try:
        with urllib.request.urlopen(req) as resp:
            result = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print(f"HTTP Error {e.code}: {e.read().decode()}", file=sys.stderr)
        sys.exit(1)

    auth["tokens"]["id_token"] = result.get("id_token", auth["tokens"]["id_token"])
    auth["tokens"]["access_token"] = result.get("access_token", auth["tokens"]["access_token"])
    if result.get("refresh_token"):
        auth["tokens"]["refresh_token"] = result["refresh_token"]
    auth["last_refresh"] = datetime.now(timezone.utc).isoformat()

    with open(AUTH_PATH, "w") as f:
        json.dump(auth, f, indent=2)

    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Codex token refreshed, expires_in={result.get('expires_in')}s")

if __name__ == "__main__":
    main()
