# Backup: TestFlight builds from GitHub

Codemagic is the main route to TestFlight (see `CODEMAGIC.md`). This backup uses GitHub's free Mac
runners for when Codemagic build credits run out. It's the **Upload to TestFlight (backup)** job in
`.github/workflows/build.yml`, and it only runs when you start it by hand.

It works the same way as the RPG game: **fastlane match** keeps one shared App Store certificate, and each
app's profile, encrypted in the private **iOS-certificates** repository (its `master` branch). The App Store
Connect key comes from that repository too: every `AuthKey_<KEY ID>.p8` there is tried until Apple accepts one.
Both GitHub and Codemagic number each build one higher than the newest build on TestFlight, so the numbers always go up.

## One-time setup: repository secrets

On github.com, open this repository, go to **Settings**, then **Secrets and variables**, then **Actions**:

| Name | Value |
|---|---|
| `MATCH_PASSWORD` | The same match password the RPG game uses (it unlocks the certificates) |
| `CERTS_REPO_TOKEN` | A fine-grained token with **Contents: Read and write** on iOS-certificates (match saves new profiles there) |
| `ASC_ISSUER_ID` | The Issuer ID: App Store Connect, Users and Access, Integrations, App Store Connect API |

Never paste a key, password or token into a chat. They only go into GitHub secrets.

## Sending a build

On GitHub, open **Actions**, then **Build**, then **Run workflow**. Pick the branch and press **Run workflow**.
The job takes about 10 minutes, then the build appears in TestFlight the same way as Codemagic builds.
