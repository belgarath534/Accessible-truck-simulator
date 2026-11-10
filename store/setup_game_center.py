"""Creates the game's Game Center achievements and leaderboards in App Store Connect (idempotent).
Run by Codemagic (workflow truck-sim-game-center) with the App Store Connect key from the integration.

  - Turns on Game Center for the app
  - Creates each achievement in game_center/achievements.json with its English text and picture
  - Creates the leaderboards (money earned, deliveries, top speed, weekly challenges)
Things that already exist are left alone, except missing text or pictures, which are added.
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

import json
from pathlib import Path

HERE = Path(__file__).parent / "game_center"
problems = []


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


def upload(kind, owner_rel, owner_kind, owner_id, file_path):
    data = file_path.read_bytes()
    item = call("POST", f"/{kind}", json={"data": {"type": kind,
                "attributes": {"fileName": file_path.name, "fileSize": len(data)},
                "relationships": {owner_rel: rel(owner_kind, owner_id)}}})["data"]
    for op in item["attributes"]["uploadOperations"]:
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        r = requests.request(op["method"], op["url"], headers=headers, data=chunk, timeout=120)
        if r.status_code >= 400:
            raise ApiError(f"Upload of {file_path.name} failed: {r.status_code} {r.text[:300]}")
    call("PATCH", f"/{kind}/{item['id']}", json={"data": {"type": kind, "id": item["id"], "attributes": {"uploaded": True}}})


app = call("GET", "/apps", params={"filter[bundleId]": BUNDLE})["data"][0]["id"]

# ------------------------------------------------------------------ Game Center for the app
detail = call("GET", f"/apps/{app}/gameCenterDetail", ok404=True)
if detail and detail.get("data"):
    detail_id = detail["data"]["id"]
    print("Game Center is already on for the app.")
else:
    detail_id = call("POST", "/gameCenterDetails", json={"data": {"type": "gameCenterDetails",
                     "relationships": {"app": rel("apps", app)}}})["data"]["id"]
    print("Turned on Game Center for the app.")

# ------------------------------------------------------------------ achievements
existing = {a["attributes"]["vendorIdentifier"]: a
            for a in all_pages(f"/gameCenterDetails/{detail_id}/gameCenterAchievements", limit=200)}
for a in json.loads((HERE / "achievements.json").read_text()):
    vendor = "trucksim." + a["id"]
    try:
        if vendor in existing:
            ach_id = existing[vendor]["id"]
        else:
            ach_id = call("POST", "/gameCenterAchievements", json={"data": {"type": "gameCenterAchievements",
                          "attributes": {"referenceName": a["title"], "vendorIdentifier": vendor, "points": a["points"],
                                         "showBeforeEarned": True, "repeatable": False},
                          "relationships": {"gameCenterDetail": rel("gameCenterDetails", detail_id)}}})["data"]["id"]
            print("Created achievement", a["title"])
        locs = call("GET", f"/gameCenterAchievements/{ach_id}/localizations")["data"]
        loc = next((l for l in locs if l["attributes"]["locale"] == "en-US"), None)
        if not loc:
            loc = call("POST", "/gameCenterAchievementLocalizations", json={"data": {
                "type": "gameCenterAchievementLocalizations",
                "attributes": {"locale": "en-US", "name": a["title"], "beforeEarnedDescription": a["detail"],
                               "afterEarnedDescription": a["detail"]},
                "relationships": {"gameCenterAchievement": rel("gameCenterAchievements", ach_id)}}})["data"]
        image = call("GET", f"/gameCenterAchievementLocalizations/{loc['id']}/gameCenterAchievementImage", ok404=True)
        if not (image and image.get("data")):
            upload("gameCenterAchievementImages", "gameCenterAchievementLocalization",
                   "gameCenterAchievementLocalizations", loc["id"], HERE / "images" / f"{a['id']}.png")
            print("  picture uploaded for", a["title"])
    except Exception as e:  # keep going with the others
        problems.append(f"Achievement {a['title']}: {e}")
        print("FAILED", a["title"], e)

# ------------------------------------------------------------------ leaderboards
LEADERBOARDS = [
    {"vendor": "trucksim.total_earned", "name": "Money Earned", "formatter": "MONEY_DOLLAR",
     "submission": "MOST_RECENT_SCORE"},
    {"vendor": "trucksim.deliveries", "name": "Deliveries", "formatter": "INTEGER",
     "submission": "MOST_RECENT_SCORE", "suffix": " deliveries", "singular": " delivery"},
    {"vendor": "trucksim.top_speed", "name": "Top Speed", "formatter": "INTEGER",
     "submission": "BEST_SCORE", "suffix": " mph", "singular": " mph"},
    {"vendor": "trucksim.weekly_challenges", "name": "Weekly Challenges Won", "formatter": "INTEGER",
     "submission": "MOST_RECENT_SCORE", "suffix": " challenges", "singular": " challenge"},
]
boards = {b["attributes"]["vendorIdentifier"]: b
          for b in all_pages(f"/gameCenterDetails/{detail_id}/gameCenterLeaderboards", limit=200)}
for b in LEADERBOARDS:
    try:
        if b["vendor"] in boards:
            board_id = boards[b["vendor"]]["id"]
        else:
            board_id = call("POST", "/gameCenterLeaderboards", json={"data": {"type": "gameCenterLeaderboards",
                            "attributes": {"referenceName": b["name"], "vendorIdentifier": b["vendor"],
                                           "defaultFormatter": b["formatter"], "submissionType": b["submission"],
                                           "scoreSortType": "DESC"},
                            "relationships": {"gameCenterDetail": rel("gameCenterDetails", detail_id)}}})["data"]["id"]
            print("Created leaderboard", b["name"])
        locs = call("GET", f"/gameCenterLeaderboards/{board_id}/localizations")["data"]
        if not any(l["attributes"]["locale"] == "en-US" for l in locs):
            attrs = {"locale": "en-US", "name": b["name"]}
            if "suffix" in b:
                attrs.update({"formatterSuffix": b["suffix"], "formatterSuffixSingular": b["singular"]})
            call("POST", "/gameCenterLeaderboardLocalizations", json={"data": {
                "type": "gameCenterLeaderboardLocalizations", "attributes": attrs,
                "relationships": {"gameCenterLeaderboard": rel("gameCenterLeaderboards", board_id)}}})
            print("  English text added for", b["name"])
    except Exception as e:
        problems.append(f"Leaderboard {b['name']}: {e}")
        print("FAILED", b["name"], e)

print()
if problems:
    print("Problems:")
    for p in problems:
        print(" -", p)
    sys.exit(1)
print("Game Center is set up: all achievements and leaderboards are in App Store Connect.")
