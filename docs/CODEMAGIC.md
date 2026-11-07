# TestFlight builds with Codemagic

`codemagic.yaml` works like Dungeon Descent's App Store workflow. It reuses the **Accessible Backrooms**
App Store Connect key and the **Accessible Backrooms Distribution** certificate already saved in Codemagic.
On its own, it registers the bundle ID `com.accessibletrucksim.TruckSim` with Apple and creates a
"Truck Sim App Store" profile. It does this the first time only and reuses them after that.

## One-time setup

1. **Add the repo to Codemagic.** In Codemagic, choose Add application, then GitHub, then
   `Accessible-truck-simulator`. It picks up `codemagic.yaml` from the repo.
2. **Create the app in App Store Connect.** On appstoreconnect.apple.com, go to Apps, press the plus
   button, then New App. Platform iOS. Pick any name that isn't taken, for example `Accessible Truck Sim`.
   Bundle ID: `com.accessibletrucksim.TruckSim`. SKU: `trucksim`.
   - If that bundle ID isn't in the list yet, start one Codemagic build first (step 3). The build registers it.
     Its upload at the end fails because the app doesn't exist yet. That's expected. Create the app,
     then build again.
3. **Start a build.** In Codemagic, choose Start new build, the branch with the latest code,
   and the workflow **Truck Sim TestFlight**.

## After each build

The upload goes to App Store Connect, and Apple processes it in about 5 to 30 minutes. Internal testers get
every build, so it appears in the TestFlight app on your iPhone. The first time, add yourself to an
Internal Testing group under the app's TestFlight tab.
