"""Gets the next App Store version ready (idempotent). Run by Codemagic (workflow truck-sim-release).

  1. Creates the version in project.yml (MARKETING_VERSION) if App Store Connect doesn't have it yet
  2. Adds Game Center to the version and releases every achievement and leaderboard with it
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

import re
from pathlib import Path


class ApiError(Exception):
    pass


def call(method, path, ok404=False, **kw):
    r = S.request(method, path if path.startswith("http") else API + path, timeout=120, **kw)
    if ok404 and r.status_code == 404:
        return None
    if r.status_code >= 400:
        raise ApiError(f"{method} {path} -> {r.status_code}: {r.text[:1200]}")
    return r.json() if r.content else {}


def rel(kind, rid):
    return {"data": {"type": kind, "id": rid}}


def all_pages(path, **params):
    out, url = [], path
    while url:
        page = call("GET", url, params=params if url == path else None)
        out += page["data"]
        url = page.get("links", {}).get("next")
    return out


# APP_VERSION overrides project.yml (to finish releasing a version after the project moved on to the next one).
VERSION = os.environ.get("APP_VERSION", "").strip() or re.search(
    r'MARKETING_VERSION: "([^"]+)"', (Path(__file__).parent.parent / "project.yml").read_text()).group(1)
app = call("GET", "/apps", params={"filter[bundleId]": BUNDLE})["data"][0]["id"]
problems = []

# ------------------------------------------------------------------ 1. the version
versions = call("GET", f"/apps/{app}/appStoreVersions", params={"filter[platform]": "IOS", "limit": 20})["data"]
version = next((v for v in versions if v["attributes"]["versionString"] == VERSION), None)
# RELEASE=manual: Apple approves it and it waits for a release-day button press (or store/release_now.py).
RELEASE_TYPE = "MANUAL" if os.environ.get("RELEASE", "").lower() == "manual" else "AFTER_APPROVAL"
if version:
    print(f"Version {VERSION} already exists ({version['attributes']['appStoreState']}).")
    if version["attributes"].get("releaseType") != RELEASE_TYPE:
        call("PATCH", f"/appStoreVersions/{version['id']}", json={"data": {
            "type": "appStoreVersions", "id": version["id"], "attributes": {"releaseType": RELEASE_TYPE}}})
else:
    version = call("POST", "/appStoreVersions", json={"data": {
        "type": "appStoreVersions", "attributes": {"platform": "IOS", "versionString": VERSION,
                                                   "releaseType": RELEASE_TYPE},
        "relationships": {"app": rel("apps", app)}}})["data"]
    print(f"Created version {VERSION}.")
print(f"Release: {'by hand, after approval' if RELEASE_TYPE == 'MANUAL' else 'automatically when Apple approves it'}.")

# ------------------------------------------------------------------ 2. Game Center with this version
detail = call("GET", f"/apps/{app}/gameCenterDetail", ok404=True)
if not (detail and detail.get("data")):
    print("Game Center isn't set up for the app (run truck-sim-game-center first).")
else:
    detail_id = detail["data"]["id"]
    try:
        call("POST", "/gameCenterAppVersions", json={"data": {"type": "gameCenterAppVersions",
             "relationships": {"appStoreVersion": rel("appStoreVersions", version["id"])}}})
        print("Game Center turned on for this version.")
    except ApiError as e:
        print("Game Center for this version:", "already on" if "409" in str(e) else e)

    def release(kind, rel_name, items_path, releases_path):
        try:
            released = {r["relationships"][rel_name]["data"]["id"]
                        for r in all_pages(releases_path, **{"include": rel_name, "limit": 200})
                        if r.get("relationships", {}).get(rel_name, {}).get("data")}
        except ApiError:
            released = set()
        items = all_pages(items_path, limit=200)
        count = 0
        for item in items:
            if item["id"] in released:
                continue
            try:
                call("POST", f"/{kind}", json={"data": {"type": kind, "relationships": {
                    "gameCenterDetail": rel("gameCenterDetails", detail_id),
                    rel_name: rel(item["type"], item["id"])}}})
                count += 1
            except ApiError as e:
                if "409" not in str(e):
                    problems.append(f"{kind} {item['attributes'].get('referenceName')}: {e}")
        print(f"{kind}: {count} new, {len(items)} in all.")

    release("gameCenterAchievementReleases", "gameCenterAchievement",
            f"/gameCenterDetails/{detail_id}/gameCenterAchievements",
            f"/gameCenterDetails/{detail_id}/achievementReleases")
    release("gameCenterLeaderboardReleases", "gameCenterLeaderboard",
            f"/gameCenterDetails/{detail_id}/gameCenterLeaderboards",
            f"/gameCenterDetails/{detail_id}/leaderboardReleases")

print()
if problems:
    print("Problems (not fatal; check them):")
    for p in problems:
        print(" -", p)
print(f"Version {VERSION} is ready for its store text, screenshots and build.")
