# Getting builds into TestFlight (no Mac needed)

GitHub's Mac builds the app, Apple signs it in the cloud, and it's uploaded to App Store Connect.
You then install it from the TestFlight app on your iPhone.

This is a one-time setup. Everything is done on websites (Safari works with VoiceOver).

## 1. Find your Team ID

1. Go to developer.apple.com/account and sign in.
2. Open **Membership details**.
3. Copy the **Team ID**. It's 10 letters and numbers, for example `AB12CD34EF`.

## 2. Register the app's bundle ID

1. On developer.apple.com, go to **Certificates, IDs & Profiles**, then **Identifiers**.
2. Press the **Add** (plus) button, choose **App IDs**, then **App**, then Continue.
3. Description: `Truck Sim`. Choose **Explicit** for the bundle ID and enter `com.accessibletrucksim.TruckSim`.
4. Continue, then Register.

If Apple says the ID is already taken, tell Claude, and it will change the ID in `project.yml`.

## 3. Create the app in App Store Connect

1. Go to appstoreconnect.apple.com, open **Apps**, and press the **Add** (plus) button, then **New App**.
2. Platform: **iOS**. Name: anything you like that isn't already taken, for example `Accessible Truck Sim`.
   You can change the name later.
3. Primary language: your choice. Bundle ID: choose `com.accessibletrucksim.TruckSim`. SKU: `trucksim`.
4. User access: Full Access. Then Create.

## 4. Create an App Store Connect API key

This key lets GitHub sign and upload for you.

1. In App Store Connect, open **Users and Access**, then the **Integrations** tab, then **App Store Connect API**.
   You may need to request access the first time.
2. Under **Team Keys**, press **Generate API Key** (or the plus button).
3. Name: `GitHub`. Access: **Admin**. Admin is required for cloud signing.
4. Write down two values from that page:
   - **Issuer ID**: shown above the list of keys.
   - **Key ID**: shown in the row for the new key.
5. **Download API Key.** Apple only lets you download it **once**. You get a file named like `AuthKey_XXXXXXXXXX.p8`.

To copy the key's text on an iPhone: in the Files app, rename the file so it ends in `.txt` instead of `.p8`.
Open it, select all, and copy. The text starts with `-----BEGIN PRIVATE KEY-----` and ends with
`-----END PRIVATE KEY-----`. Copy all of it, including those lines.

**Never paste this key into a chat**, including with Claude. It only goes into GitHub secrets (next step).

## 5. Add four secrets on GitHub

1. Open the repository on github.com, go to **Settings**, then **Secrets and variables**, then **Actions**.
2. Press **New repository secret** four times to add:

| Name | Value |
|---|---|
| `APPLE_TEAM_ID` | Team ID from step 1 |
| `ASC_KEY_ID` | Key ID from step 4 |
| `ASC_ISSUER_ID` | Issuer ID from step 4 |
| `ASC_KEY_P8` | Full text of the `.p8` key file |

## 6. Send a build to TestFlight

Either:
- On GitHub, open **Actions**, then **Build**, then **Run workflow**. Pick the branch and press **Run workflow**.
- Or ask Claude to push a commit with `[testflight]` in its message.

The upload takes about 10 minutes. Apple then processes the build, which usually takes 5 to 30 minutes.

## 7. Install it

1. In App Store Connect, open the app, then **TestFlight**.
2. Under **Internal Testing**, create a group (for example `Me`) and add yourself as a tester.
3. Open the TestFlight app on your iPhone. Truck Sim appears there; press **Install**.

Later builds show up in TestFlight automatically.
