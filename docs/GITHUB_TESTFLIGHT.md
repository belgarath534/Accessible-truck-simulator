# Backup: TestFlight builds from GitHub

Codemagic is the main route to TestFlight (see `CODEMAGIC.md`). This backup uses GitHub's free Mac
runners for when Codemagic build credits run out. It's the **Upload to TestFlight (backup)** job in
`.github/workflows/build.yml`, and it only runs when you start it by hand.

Apple signs the app in the cloud, so no certificate file is needed, just an App Store Connect API key.
Builds from GitHub are numbered from 10001 up, so they never clash with Codemagic's build numbers.

## One-time setup: four repository secrets

On github.com, open the repository, go to **Settings**, then **Secrets and variables**, then **Actions**,
then **New repository secret**. Add:

| Name | Value |
|---|---|
| `APPLE_TEAM_ID` | Your Team ID: developer.apple.com/account, Membership details |
| `ASC_KEY_ID` | The API key's Key ID (App Store Connect, Users and Access, Integrations, App Store Connect API) |
| `ASC_ISSUER_ID` | The Issuer ID, shown near the top of that same page |
| `ASC_KEY_P8` | The full text of the `AuthKey_XXXXXXXXXX.p8` file, including the BEGIN and END lines |

You can reuse the key you already use for Dungeon Descent's uploader. It must have **Admin** access,
because Apple's cloud signing requires it. If it doesn't, make a new Admin key just for this.

Never paste the `.p8` key into a chat. It only goes into GitHub secrets.

## Sending a build

On GitHub, open **Actions**, then **Build**, then **Run workflow**. Pick the branch and press **Run workflow**.
The job takes about 10 minutes, then the build appears in TestFlight the same way as Codemagic builds.
