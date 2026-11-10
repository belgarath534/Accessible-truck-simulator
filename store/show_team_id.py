"""Prints the Apple Team ID (and the key and issuer IDs Codemagic uses), for setting up the GitHub
TestFlight backup. None of these are secrets: the private key stays in Codemagic."""
import os
import time

import jwt
import requests

key = os.environ["APP_STORE_CONNECT_PRIVATE_KEY"].strip().replace("\\n", "\n")
now = int(time.time())
token = jwt.encode({"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": now, "exp": now + 600,
                    "aud": "appstoreconnect-v1"}, key, algorithm="ES256",
                   headers={"kid": os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"], "typ": "JWT"})
r = requests.get("https://api.appstoreconnect.apple.com/v1/bundleIds",
                 params={"filter[identifier]": "com.accessibletrucksim.TruckSim"},
                 headers={"Authorization": "Bearer " + token}, timeout=60)
r.raise_for_status()
data = r.json()["data"]
print("TEAM ID:", data[0]["attributes"]["seedId"] if data else "not found")
print("KEY ID:", os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"])
print("ISSUER ID:", os.environ["APP_STORE_CONNECT_ISSUER_ID"])
