"""Releases the approved App Store version that is waiting for a manual release ("Pending Developer Release").
Run by the GitHub "Release to the App Store" workflow (release now = yes), with the usual App Store Connect settings."""
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
    return key.replace("\\n", "\n").strip()


now = int(time.time())
TOKEN = jwt.encode({"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": now, "exp": now + 1000,
                    "aud": "appstoreconnect-v1"}, private_key(), algorithm="ES256",
                   headers={"kid": os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"], "typ": "JWT"})
H = {"Authorization": "Bearer " + TOKEN}

app = requests.get(f"{API}/apps", params={"filter[bundleId]": BUNDLE}, headers=H, timeout=60).json()["data"][0]["id"]
versions = requests.get(f"{API}/apps/{app}/appStoreVersions", params={"filter[platform]": "IOS", "limit": 10},
                        headers=H, timeout=60).json()["data"]
for v in versions:
    print(f"version {v['attributes']['versionString']}: {v['attributes']['appStoreState']}")
waiting = [v for v in versions if v["attributes"]["appStoreState"] == "PENDING_DEVELOPER_RELEASE"]
if not waiting:
    sys.exit("No version is waiting for release (it may still be in review, or already out).")
v = waiting[0]
r = requests.post(f"{API}/appStoreVersionReleaseRequests", headers=H, timeout=60, json={"data": {
    "type": "appStoreVersionReleaseRequests",
    "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
if r.status_code >= 400:
    sys.exit(f"Apple refused the release: {r.status_code} {r.text[:800]}")
print(f"Released version {v['attributes']['versionString']}! It reaches the App Store within a few hours.")
