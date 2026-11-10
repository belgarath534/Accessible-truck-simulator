# Backup: TestFlight builds from GitHub

Codemagic is the main route to TestFlight (see `CODEMAGIC.md`). This backup uses GitHub's free Mac
runners for when Codemagic build credits run out. It's the **Upload to TestFlight (backup)** job in
`.github/workflows/build.yml`, and it only runs when you start it by hand.

Apple signs the app in the cloud, so no certificate file is needed, just an App Store Connect API key.
Builds from GitHub are numbered from 10001 up, so they never clash with Codemagic's build numbers.

## One-time setup: three repository secrets

The key itself comes from the private **iOS-certificates** repository (`AuthKey_<KEY ID>.p8`; the Key ID is
read from the file name). This public repository needs a token to read it, plus two IDs that aren't in any file.

On github.com, open this repository, go to **Settings**, then **Secrets and variables**, then **Actions**,
then **New repository secret**. Add:

| Name | Value |
|---|---|
| `CERTS_REPO_TOKEN` | A fine-grained personal access token that can read iOS-certificates (see below) |
| `APPLE_TEAM_ID` | Your Team ID: developer.apple.com/account, Membership details |
| `ASC_ISSUER_ID` | The Issuer ID: App Store Connect, Users and Access, Integrations, App Store Connect API, near the top |

Optional: `ASC_KEY_ID` picks one key when iOS-certificates holds several (otherwise the first one is used).
The old way still works too: `ASC_KEY_ID` plus `ASC_KEY_P8` (the key's full text) instead of the token.

**Making the token:** github.com, your picture, **Settings**, **Developer settings**, **Personal access tokens**,
**Fine-grained tokens**, **Generate new token**. Repository access: **Only select repositories**, pick
**iOS-certificates**. Permissions: **Contents: Read-only**. Generate, copy it, and paste it into the
`CERTS_REPO_TOKEN` secret.

The key must have **Admin** access in App Store Connect, because Apple's cloud signing requires it.

Never paste a key or token into a chat. They only go into GitHub secrets.

## Sending a build

On GitHub, open **Actions**, then **Build**, then **Run workflow**. Pick the branch and press **Run workflow**.
The job takes about 10 minutes, then the build appears in TestFlight the same way as Codemagic builds.
