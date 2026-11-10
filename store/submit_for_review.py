"""Gets Accessible Truck Sim ready for sale and sends it to App Review. Run by Codemagic
(workflow truck-sim-submit), with the same App Store Connect key as fill_store_info.py.

Steps (each skipped if already done):
  1. Price: free, in every country
  2. Availability: every country, and new countries Apple adds later
  3. Build: the newest processed build is attached to the version waiting for submission
  4. Submit for review (only when SUBMIT=yes)

The App Privacy answers can't be set with Apple's API: those are done by hand in App Store Connect.
"""
import os
import sys
import time

import jwt
import requests

API = "https://api.appstoreconnect.apple.com"
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


class ApiError(Exception):
    pass


def call(method, path, ok404=False, **kw):
    url = path if path.startswith("http") else API + (path if path.startswith("/v") else "/v1" + path)
    r = S.request(method, url, timeout=60, **kw)
    if ok404 and r.status_code == 404:
        return None
    if r.status_code >= 400:
        raise ApiError(f"{method} {path} -> {r.status_code}: {r.text[:1500]}")
    return r.json() if r.content else {}


def all_pages(path, **params):
    out, url = [], path
    while url:
        page = call("GET", url, params=params if url == path else None)
        out += page["data"]
        url = page.get("links", {}).get("next")
    return out


def rel(kind, rid):
    return {"data": {"type": kind, "id": rid}}


apps = call("GET", "/apps", params={"filter[bundleId]": BUNDLE})["data"]
if not apps:
    sys.exit(f"No app with bundle id {BUNDLE} in App Store Connect.")
APP = apps[0]["id"]
print(f"App: {apps[0]['attributes']['name']} ({APP})")
problems = []

# ------------------------------------------------------------------ 1. price: free
try:
    existing = call("GET", f"/apps/{APP}/appPriceSchedule", ok404=True)
    if existing and existing.get("data"):
        prices = call("GET", f"/appPriceSchedules/{existing['data']['id']}/manualPrices",
                      params={"include": "appPricePoint"}, ok404=True)
        points = [i for i in (prices or {}).get("included", []) if i["type"] == "appPricePoints"]
        print("1. Price schedule already set:", [p["attributes"].get("customerPrice") for p in points])
        if points and all(float(p["attributes"].get("customerPrice") or 0) == 0 for p in points):
            existing = "free"
    if existing != "free":
        points = all_pages(f"/apps/{APP}/appPricePoints", **{"filter[territory]": "USA", "limit": 200})
        free = next(p for p in points if float(p["attributes"]["customerPrice"]) == 0)
        call("POST", "/appPriceSchedules", json={
            "data": {"type": "appPriceSchedules", "relationships": {
                "app": rel("apps", APP),
                "baseTerritory": rel("territories", "USA"),
                "manualPrices": {"data": [{"type": "appPrices", "id": "${free}"}]}}},
            "included": [{"type": "appPrices", "id": "${free}", "attributes": {"startDate": None},
                          "relationships": {"appPricePoint": rel("appPricePoints", free["id"])}}]})
        print("1. Price set to free.")
except Exception as e:
    problems.append(f"Price: {e}")
    print("1. Price FAILED:", e)

# ------------------------------------------------------------------ 2. availability: everywhere
try:
    avail = call("GET", f"/apps/{APP}/appAvailabilityV2", ok404=True)
    if avail and avail.get("data"):
        print("2. Availability already set (new territories:",
              avail["data"]["attributes"].get("availableInNewTerritories"), ")")
    else:
        territories = all_pages("/territories", limit=200)
        items, refs = [], []
        for t in territories:
            local = "${" + t["id"] + "}"
            refs.append({"type": "territoryAvailabilities", "id": local})
            items.append({"type": "territoryAvailabilities", "id": local, "attributes": {"available": True},
                          "relationships": {"territory": rel("territories", t["id"])}})
        call("POST", "/v2/appAvailabilities", json={
            "data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
                     "relationships": {"app": rel("apps", APP), "territoryAvailabilities": {"data": refs}}},
            "included": items})
        print(f"2. Available in all {len(territories)} countries and regions.")
except Exception as e:
    problems.append(f"Availability: {e}")
    print("2. Availability FAILED:", e)

# ------------------------------------------------------------------ 3. attach the newest build
version = None
try:
    versions = call("GET", f"/apps/{APP}/appStoreVersions",
                    params={"filter[platform]": "IOS", "limit": 10})["data"]
    editable = [v for v in versions if v["attributes"]["appStoreState"] in
                ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")]
    for v in versions:
        print(f"   version {v['attributes']['versionString']}: {v['attributes']['appStoreState']}")
    if not editable:
        raise ApiError("no version is waiting for submission (already submitted?)")
    version = editable[0]
    # The newest build of this version, waiting (up to 30 minutes) while Apple processes it.
    want = version["attributes"]["versionString"]
    build = None
    for attempt in range(31):
        newest = call("GET", "/builds", params={"filter[app]": APP, "sort": "-uploadedDate", "limit": 1,
                                                "filter[preReleaseVersion.version]": want})["data"]
        if newest and newest[0]["attributes"]["processingState"] == "VALID":
            build = newest[0]
            break
        state = newest[0]["attributes"]["processingState"] if newest else "no build yet"
        print(f"   waiting for build of {want} ({state})...")
        time.sleep(60)
    if not build:
        raise ApiError(f"no processed build of version {want}")
    call("PATCH", f"/appStoreVersions/{version['id']}/relationships/build", json=rel("builds", build["id"]))
    print(f"3. Build {build['attributes']['version']} attached to version {version['attributes']['versionString']}.")
except Exception as e:
    problems.append(f"Build: {e}")
    print("3. Build FAILED:", e)

# ------------------------------------------------------------------ 4. submit
if os.environ.get("SUBMIT") != "yes":
    print("4. Not submitting (SUBMIT is not yes).")
elif version and not problems:
    try:
        open_subs = call("GET", "/reviewSubmissions", params={"filter[app]": APP, "filter[platform]": "IOS",
                                                              "filter[state]": "READY_FOR_REVIEW"})["data"]
        if open_subs:
            sub = open_subs[0]
        else:
            sub = call("POST", "/reviewSubmissions", json={"data": {
                "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                "relationships": {"app": rel("apps", APP)}}})["data"]
        try:
            # Freshly uploaded screenshots take Apple a few minutes to process: wait and try again.
            for attempt in range(20):
                try:
                    call("POST", "/reviewSubmissionItems", json={"data": {
                        "type": "reviewSubmissionItems", "relationships": {
                            "reviewSubmission": rel("reviewSubmissions", sub["id"]),
                            "appStoreVersion": rel("appStoreVersions", version["id"])}}})
                    break
                except ApiError as e:
                    if "ASSET_IN_POST_PROCESSING" not in str(e) or attempt == 19:
                        raise
                    print("   Apple is still processing the screenshots; waiting a minute...")
                    time.sleep(60)
        except ApiError as e:
            items = call("GET", f"/reviewSubmissions/{sub['id']}/items")["data"]
            if not items:
                # Apple refused to add the version: its reason says what's missing.
                raise
            print("   (version was already in the submission)")
        call("PATCH", f"/reviewSubmissions/{sub['id']}", json={"data": {
            "type": "reviewSubmissions", "id": sub["id"], "attributes": {"submitted": True}}})
        print("4. SUBMITTED for App Review.")
    except Exception as e:
        problems.append(f"Submit: {e}")
        print("4. Submit FAILED:", e)
else:
    print("4. Not submitting because an earlier step failed.")

print()
if problems:
    print("Problems:")
    for p in problems:
        print(" -", p)
    sys.exit(1)
print("All done.")
