"""Fills in Accessible Truck Sim's App Store Connect information. Run by Codemagic
(uses the "Accessible Backrooms" App Store Connect key from the integration).

Safe to run again and again: it only sets things to the text in store/en-US.
Each part runs on its own, so one failure does not stop the rest; a summary is
printed at the end.

What it fills in:
  TestFlight   beta description, feedback email, beta review contact and notes,
               "What to Test" on recent builds, and an internal tester group
               copied from Dungeon Descent's internal testers
  App Store    subtitle, description, keywords, promotional text, support and
               privacy URLs, category, age rating, content rights, copyright,
               App Review contact and notes

Contact details (name, email, phone) are copied from Dungeon Descent, which is
on the same account, so they never have to be typed into this repository.
"""
import os
import sys
import time
from pathlib import Path

import jwt
import requests

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE = "com.accessibletrucksim.TruckSim"
DD_BUNDLE = "com.dungeon.descent"
REPO = "https://github.com/belgarath534/Accessible-truck-simulator"
SUPPORT_URL = REPO + "/issues"
PRIVACY_URL = REPO + "/blob/HEAD/docs/PRIVACY.md"
TEXT = Path(__file__).parent / "en-US"


def text(name):
    return (TEXT / name).read_text(encoding="utf-8").strip()


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
    r = S.request(method, path if path.startswith("http") else API + path, timeout=60, **kw)
    if ok404 and r.status_code == 404:
        return None
    if r.status_code >= 400:
        raise ApiError(f"{method} {path} -> {r.status_code}: {r.text[:600]}")
    return r.json() if r.content else {}


def patch(kind, rid, attributes=None, relationships=None):
    data = {"type": kind, "id": rid}
    if attributes:
        data["attributes"] = attributes
    if relationships:
        data["relationships"] = relationships
    return call("PATCH", f"/{kind}/{rid}", json={"data": data})


def rel(kind, rid):
    return {"data": {"type": kind, "id": rid}}


done, failed = [], []


def part(name):
    def wrap(fn):
        try:
            result = fn()
            done.append(name + (f": {result}" if result else ""))
        except Exception as e:  # keep going with the other parts
            failed.append(f"{name}: {e}")
        return fn
    return wrap


# ---------------------------------------------------------------- find the apps
apps = call("GET", "/apps", params={"filter[bundleId]": BUNDLE})["data"]
if not apps:
    print(f"The app {BUNDLE} does not exist in App Store Connect yet.")
    print("Create it on appstoreconnect.apple.com (Apps, plus button, New App) and run this again.")
    sys.exit(0)
APP = apps[0]["id"]
print(f"Truck Sim app: {apps[0]['attributes'].get('name')} ({APP})")

dd_apps = call("GET", "/apps", params={"filter[bundleId]": DD_BUNDLE})["data"]
DD = dd_apps[0]["id"] if dd_apps else None

# Contact details from Dungeon Descent (TestFlight review details first, App Store review details second).
CONTACT_FIELDS = ("contactFirstName", "contactLastName", "contactPhone", "contactEmail")
contact = {}
if DD:
    try:
        d = (call("GET", f"/apps/{DD}/betaAppReviewDetail", ok404=True) or {}).get("data")
        if d:
            contact.update({k: d["attributes"][k] for k in CONTACT_FIELDS if d["attributes"].get(k)})
        if len(contact) < len(CONTACT_FIELDS):
            vers = call("GET", f"/apps/{DD}/appStoreVersions", params={"filter[platform]": "IOS", "limit": 5})["data"]
            for v in vers:
                r = (call("GET", f"/appStoreVersions/{v['id']}/appStoreReviewDetail", ok404=True) or {}).get("data")
                if r:
                    for k in CONTACT_FIELDS:
                        if not contact.get(k) and r["attributes"].get(k):
                            contact[k] = r["attributes"][k]
                if len(contact) == len(CONTACT_FIELDS):
                    break
    except ApiError as e:
        failed.append(f"Reading contact details from Dungeon Descent: {e}")
print("Contact details found:", ", ".join(sorted(contact)) or "none")
feedback_email = contact.get("contactEmail")
if DD and not feedback_email:
    try:
        for loc in call("GET", f"/apps/{DD}/betaAppLocalizations")["data"]:
            if loc["attributes"].get("feedbackEmail"):
                feedback_email = loc["attributes"]["feedbackEmail"]
                break
    except ApiError:
        pass


# ---------------------------------------------------------------- TestFlight
@part("TestFlight description and feedback email")
def _():
    attrs = {"description": text("testflight/description.txt"), "privacyPolicyUrl": PRIVACY_URL,
             "marketingUrl": REPO}
    if feedback_email:
        attrs["feedbackEmail"] = feedback_email
    locs = call("GET", f"/apps/{APP}/betaAppLocalizations")["data"]
    en = next((l for l in locs if l["attributes"]["locale"] == "en-US"), None)
    if en:
        patch("betaAppLocalizations", en["id"], attrs)
    else:
        call("POST", "/betaAppLocalizations", json={"data": {"type": "betaAppLocalizations",
             "attributes": {"locale": "en-US", **attrs}, "relationships": {"app": rel("apps", APP)}}})
    return "with feedback email" if feedback_email else "no feedback email found"


@part("TestFlight beta review contact and notes")
def _():
    d = call("GET", f"/apps/{APP}/betaAppReviewDetail")["data"]
    patch("betaAppReviewDetails", d["id"], {**contact, "demoAccountRequired": False,
                                            "notes": text("review_notes.txt")})


@part("TestFlight 'What to Test'")
def _():
    builds = call("GET", "/builds", params={"filter[app]": APP, "sort": "-uploadedDate", "limit": 5})["data"]
    if not builds:
        return "no builds uploaded yet"
    whats_new = text("testflight/what_to_test.txt")
    for b in builds:
        locs = call("GET", f"/builds/{b['id']}/betaBuildLocalizations")["data"]
        en = next((l for l in locs if l["attributes"]["locale"] == "en-US"), None)
        if en:
            patch("betaBuildLocalizations", en["id"], {"whatsNew": whats_new})
        else:
            call("POST", "/betaBuildLocalizations", json={"data": {"type": "betaBuildLocalizations",
                 "attributes": {"locale": "en-US", "whatsNew": whats_new},
                 "relationships": {"build": rel("builds", b["id"])}}})
    return "builds " + ", ".join(b["attributes"]["version"] for b in builds)


@part("Internal tester group")
def _():
    groups = call("GET", f"/apps/{APP}/betaGroups")["data"]
    group = next((g for g in groups if g["attributes"].get("isInternalGroup")), None)
    if not group:
        group = call("POST", "/betaGroups", json={"data": {"type": "betaGroups",
                     "attributes": {"name": "Internal Testers", "isInternalGroup": True, "hasAccessToAllBuilds": True},
                     "relationships": {"app": rel("apps", APP)}}})["data"]
    if not DD:
        return f"group '{group['attributes']['name']}' (no Dungeon Descent testers to copy)"
    have = {t["attributes"].get("email", "").lower()
            for t in call("GET", f"/betaGroups/{group['id']}/betaTesters", params={"limit": 200})["data"]}
    added = 0
    for g in call("GET", f"/apps/{DD}/betaGroups")["data"]:
        if not g["attributes"].get("isInternalGroup"):
            continue
        for t in call("GET", f"/betaGroups/{g['id']}/betaTesters", params={"limit": 200})["data"]:
            email = (t["attributes"].get("email") or "").lower()
            if not email or email in have:
                continue
            attrs = {k: t["attributes"][k] for k in ("email", "firstName", "lastName") if t["attributes"].get(k)}
            call("POST", "/betaTesters", json={"data": {"type": "betaTesters", "attributes": attrs,
                 "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group["id"]}]}}}})
            have.add(email)
            added += 1
    return f"group '{group['attributes']['name']}', {len(have)} tester(s), {added} added now"


# ---------------------------------------------------------------- App Store listing
def editable_app_info():
    infos = call("GET", f"/apps/{APP}/appInfos")["data"]
    for i in infos:
        state = i["attributes"].get("appStoreState") or i["attributes"].get("state")
        if state in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED",
                     "WAITING_FOR_REVIEW", None):
            return i
    return infos[0]


@part("Category (Games: Simulation, Racing)")
def _():
    info = editable_app_info()
    patch("appInfos", info["id"], relationships={
        "primaryCategory": rel("appCategories", "GAMES"),
        "primarySubcategoryOne": rel("appCategories", "GAMES_SIMULATION"),
        "primarySubcategoryTwo": rel("appCategories", "GAMES_RACING"),
    })


@part("Subtitle and privacy policy URL")
def _():
    info = editable_app_info()
    locs = call("GET", f"/appInfos/{info['id']}/appInfoLocalizations")["data"]
    en = next((l for l in locs if l["attributes"]["locale"] == "en-US"), locs[0] if locs else None)
    if not en:
        raise ApiError("no app info localization")
    patch("appInfoLocalizations", en["id"], {"subtitle": text("subtitle.txt"), "privacyPolicyUrl": PRIVACY_URL})
    return f"locale {en['attributes']['locale']}"


@part("Age rating (no objectionable content)")
def _():
    info = editable_app_info()
    decl = call("GET", f"/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    current = decl["attributes"]
    attrs = {}
    for k, v in current.items():
        # Every "how much" question is NONE and every yes/no question is false: it's a driving game
        # with no violence, chat, web access, purchases or user-generated content.
        if k in ("kidsAgeBand", "ageRatingOverride", "koreaAgeRatingOverride", "ageRatingOverrideV2"):
            continue
        if isinstance(v, bool) or v is None and k.startswith(("gambling", "unrestricted", "lootBox", "messaging",
                                                               "userGenerated", "advertising", "ageAssurance",
                                                               "healthOrWellness", "parentalControls")):
            attrs[k] = False
        elif isinstance(v, str) or v is None:
            attrs[k] = "NONE"
    try:
        patch("ageRatingDeclarations", decl["id"], attrs)
    except ApiError:
        # Retry without fields Apple rejects for this account's API version.
        attrs = {k: v for k, v in attrs.items() if v is False or k in (
            "alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "horrorOrFearThemes",
            "matureOrSuggestiveThemes", "medicalOrTreatmentInformation", "profanityOrCrudeHumor",
            "sexualContentGraphicAndNudity", "sexualContentOrNudity", "violenceCartoonOrFantasy",
            "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic")}
        patch("ageRatingDeclarations", decl["id"], attrs)
    return f"{len(attrs)} answers"


@part("Content rights (no third-party content)")
def _():
    patch("apps", APP, {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"})


def editable_version():
    vers = call("GET", f"/apps/{APP}/appStoreVersions", params={"filter[platform]": "IOS"})["data"]
    for v in vers:
        state = v["attributes"].get("appStoreState") or v["attributes"].get("appVersionState")
        if state in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"):
            return v
    return None


@part("App Store description, keywords, promotional text, URLs")
def _():
    v = editable_version()
    if not v:
        return "no editable App Store version"
    locs = call("GET", f"/appStoreVersions/{v['id']}/appStoreVersionLocalizations")["data"]
    en = next((l for l in locs if l["attributes"]["locale"] == "en-US"), locs[0] if locs else None)
    attrs = {"description": text("description.txt"), "keywords": text("keywords.txt"),
             "promotionalText": text("promotional_text.txt"), "supportUrl": SUPPORT_URL, "marketingUrl": REPO}
    if en:
        patch("appStoreVersionLocalizations", en["id"], attrs)
    else:
        call("POST", "/appStoreVersionLocalizations", json={"data": {"type": "appStoreVersionLocalizations",
             "attributes": {"locale": "en-US", **attrs},
             "relationships": {"appStoreVersion": rel("appStoreVersions", v["id"])}}})
    return f"version {v['attributes']['versionString']}"


@part("Copyright")
def _():
    v = editable_version()
    if not v:
        return "no editable App Store version"
    holder = " ".join(x for x in (contact.get("contactFirstName"), contact.get("contactLastName")) if x)
    if not holder:
        return "skipped: no name found"
    patch("appStoreVersions", v["id"], {"copyright": f"{time.gmtime().tm_year} {holder}"})


@part("App Review contact and notes")
def _():
    v = editable_version()
    if not v:
        return "no editable App Store version"
    attrs = {**contact, "demoAccountRequired": False, "notes": text("review_notes.txt")}
    r = (call("GET", f"/appStoreVersions/{v['id']}/appStoreReviewDetail", ok404=True) or {}).get("data")
    if r:
        patch("appStoreReviewDetails", r["id"], attrs)
    else:
        call("POST", "/appStoreReviewDetails", json={"data": {"type": "appStoreReviewDetails", "attributes": attrs,
             "relationships": {"appStoreVersion": rel("appStoreVersions", v["id"])}}})


print()
print("Done:")
for d in done:
    print("  ✓", d)
if failed:
    print("Could not do:")
    for f in failed:
        print("  ✗", f)
print()
print("Can't be done through Apple's API (do these on the website when you want to go public):")
print("  - App Privacy answers (App Store Connect, App Privacy): choose 'Data Not Collected'")
print("  - Screenshots for the App Store listing")
print("  - Pricing and availability")
