# Shipping on the Mac App Store

What is already in the repository, what was measured, and what is left — none of which is
code.

The app is **not** on the App Store today. `Scripts/build-app.sh` stays the normal way to
build it, and nothing here changes that.

## What is ready

| Piece | Where | State |
| --- | --- | --- |
| Sandbox entitlements | `Resources/NotchOTP-AppStore.entitlements` | sandbox + smart card; verified against a real key |
| Xcode project (generated) | `project.yml` → `NotchOTP.xcodeproj` | builds and archives; not committed |
| Archive + export | `Scripts/archive-app.sh` | archive, export the `.pkg`, optional upload |
| Export options | `Scripts/ExportOptions-AppStore.plist` | `app-store-connect`, `Apple Distribution` |
| Demo mode in release | `-demo` launch argument | compiled into the release build, on purpose |
| Bundle metadata | `Resources/Info.plist` | identifier `app.notchotp`, category `public.app-category.utilities`, `LSUIElement` |

**Measured on macOS 26** — the sandbox does not cost the app anything:

```
codesign -d --entitlements - …  →  com.apple.security.app-sandbox, com.apple.security.smartcard
launch with the sandbox engaged →  AppSandbox (libsystem_secinit)
                                   accounts listed: 10        ← a real YubiKey, over PC/SC
                                   embedded biometric prompt up, evaluatePolicy starting
no denial in the unified log
```

`** ARCHIVE SUCCEEDED **` on a local archive, with those two entitlements in the archived app
and no nested framework to sign (the kit is a static library, like SwiftPM produces).

## What only you can do

1. **Apple Developer Program**, paid, and Xcode signed into it.
2. **Register the bundle identifier** `app.notchotp` in Certificates, Identifiers &
   Profiles, and create the **app record** in App Store Connect.
3. **Run the archive** — the certificates and the Mac App Store provisioning profile are
   created on the way:

   ```bash
   TEAM_ID=ABCDE12345 Scripts/archive-app.sh
   ```

4. **Upload**: Xcode's Organizer, Transporter.app, or the same script with an App Store
   Connect API key:

   ```bash
   TEAM_ID=ABCDE12345 ASC_KEY_ID=… ASC_ISSUER_ID=… Scripts/archive-app.sh --upload
   ```

5. **The listing**: description, the 1024×1024 icon (the bundle carries an `.icns`; the
   marketing icon is uploaded in App Store Connect), screenshots (the two in `docs/` show
   the panel; App Store Connect wants 1280×800 or larger), privacy — "Data not collected",
   which is the truth here.

## Two things that decide whether it passes

**The reviewer has no YubiKey.** An app that answers "plug in your key" to the reviewer is
the classic rejection. The `-demo` argument swaps in a fake key and a fake sensor, and it is
now compiled into the release build — say so in *Notes for Review*:

> NotchOTP needs a YubiKey. To try it without one:
> `open -a NotchOTP --args -demo` — the panel then lists four demo accounts, and the
> fingerprint prompt is simulated. `open -a NotchOTP --args -demo -confirm` opens the
> panel and confirms the first account straight away.

**The name.** "NotchOTP" contains Yubico's trademark, and Apple rejects app names that
use someone else's mark. Decide before spending the review round: rename (the repository,
the bundle identifier, `CFBundleName`, the README, the `.entitlements` and the docs all
carry it) or obtain Yubico's blessing.

Two smaller ones: the donation link must stay **out of the app** (guideline 3.1.1 forbids
pointing at an external purchase mechanism; it lives in the README, which is fine), and the
QR scanner asks for Screen Recording — allowed with the user's consent, and the app must
stay usable if it is refused. It is.

## What changes in the sandboxed build

- The **smart card** entitlement is what keeps the key reachable: the app talks to the
  PC/SC service, never to the USB device directly, so no `com.apple.security.device.usb` is
  needed.
- With a real provisioning profile, the **data-protection keychain** becomes usable, so the
  OATH password can move from the session keychain to an item protected by biometry
  (`SecAccessControl` + `kSecUseDataProtectionKeychain`). Today's documented compromise —
  an item any process running as you could read — would go away.
- Nothing is written to disk and nothing goes over the network, so no file or network
  entitlement is required.

## To check by hand once it is signed

The sandbox path was verified for the key, the keychain and biometrics. Three things were
not, because they need a signed build and a human:

- **Screen Recording** (QR scanning): grant, refuse, and confirm the refusal path shows the
  instructions instead of failing silently.
- **Launch at login** (`SMAppService.mainApp`): toggle it in the settings and check the
  system login items.
- **Display sleep, session lock, key unplugged**: the three moments that must wipe the
  revealed codes.
