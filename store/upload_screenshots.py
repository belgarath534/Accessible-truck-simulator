"""Uploads App Store screenshots (6.9-inch iPhone) from a folder to the editable App Store version.
Run by the Codemagic "truck-sim-screenshots" workflow with UPLOAD=yes. Replaces the screenshots that are there.

  python3 store/upload_screenshots.py shots/
"""
import hashlib
import os
import sys
import time

import jwt
import requests

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE = "com.accessibletrucksim.TruckSim"


def private_key():
    key = os.environ["APP_STORE_CONNECT_PRIVATE_KEY"].strip()
    if key.startswith("@file:"):
        key = open(os.path.expanduser(key[6:])).read()
    elif key.startswith("@env:"):
        key = os.environ[key[5:]]
    key = key.replace("\\n", "\n").strip().strip('"')
    if "BEGIN" not in key:
        body = "".join(key.split())
        key = "-----BEGIN PRIVATE KEY-----\n" + "\n".join(body[i:i + 64] for i in range(0, len(body), 64)) + "\n-----END PRIVATE KEY-----"
    return key


def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": now, "exp": now + 1000,
                       "aud": "appstoreconnect-v1"}, private_key(), algorithm="ES256",
                      headers={"kid": os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"], "typ": "JWT"})

S = requests.Session()
S.headers["Authorization"] = "Bearer " + token()


def call(method, path, **kw):
    r = S.request(method, path if path.startswith("http") else API + path, timeout=120, **kw)
    if r.status_code >= 400:
        sys.exit(f"{method} {path} -> {r.status_code}: {r.text[:800]}")
    return r.json() if r.content else {}


folder = sys.argv[1]
files = sorted(f for f in os.listdir(folder) if f.endswith(".png") and f[0].isdigit())
if not files:
    sys.exit("No screenshots found")

app = call("GET", "/apps", params={"filter[bundleId]": BUNDLE})["data"][0]["id"]
versions = call("GET", f"/apps/{app}/appStoreVersions", params={"filter[platform]": "IOS"})["data"]
version = next(v for v in versions if (v["attributes"].get("appStoreState") or v["attributes"].get("appVersionState"))
               in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"))
locs = call("GET", f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]
loc = next((l for l in locs if l["attributes"]["locale"] == "en-US"), locs[0])

sets = call("GET", f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]
target = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == "APP_IPHONE_67"), None)
if not target:
    target = call("POST", "/appScreenshotSets", json={"data": {"type": "appScreenshotSets",
                  "attributes": {"screenshotDisplayType": "APP_IPHONE_67"},
                  "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}}}}})["data"]
for old in call("GET", f"/appScreenshotSets/{target['id']}/appScreenshots")["data"]:
    call("DELETE", f"/appScreenshots/{old['id']}")
    print("Removed old screenshot", old["attributes"].get("fileName"))

for name in files:
    data = open(os.path.join(folder, name), "rb").read()
    shot = call("POST", "/appScreenshots", json={"data": {"type": "appScreenshots",
                "attributes": {"fileName": name, "fileSize": len(data)},
                "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": target["id"]}}}}})["data"]
    for op in shot["attributes"]["uploadOperations"]:
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        r = requests.request(op["method"], op["url"], headers=headers, data=chunk, timeout=120)
        if r.status_code >= 400:
            sys.exit(f"Upload of {name} failed: {r.status_code} {r.text[:300]}")
    call("PATCH", f"/appScreenshots/{shot['id']}", json={"data": {"type": "appScreenshots", "id": shot["id"],
         "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    print("Uploaded", name)
print(f"Done: {len(files)} screenshots on version {version['attributes']['versionString']}")
