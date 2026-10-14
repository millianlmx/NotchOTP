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
| Screenshots | `docs/app-store/screenshots/` | four shots per language, English and French — see [Screenshots](#screenshots) |
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

4. **Upload**: Xcode's Organizer, Transporter.app, or the same script — which uploads through
   Xcode's own account session, no API key to handle:

   ```bash
   TEAM_ID=ABCDE12345 Scripts/archive-app.sh --upload
   ```

   With an App Store Connect API key in the environment (`ASC_KEY_ID`, `ASC_ISSUER_ID` and
   `ASC_KEY_PATH`, the key coming from App Store Connect → Users and Access → Integrations)
   xcodebuild signs, provisions and uploads with the key instead of the account session —
   that is what the release workflow below relies on.

5. **The listing**: description, the 1024×1024 icon (the bundle carries an `.icns`; the
   marketing icon is uploaded in App Store Connect), screenshots, and privacy — "Data not
   collected", which is the truth here.

   For the screenshots, capture the panel window **alone** and compose it, rather than
   photographing the desktop:

   ```bash
   # the window number comes from CGWindowListCopyWindowInfo, filtering on the owner name
   screencapture -x -o -l <window number> panel.png      # alpha, no shadow, no desktop
   ```

   Then draw it hung from the top edge of a 2560×1600 canvas. The whole thing is scripted —
   see **[Screenshots](#screenshots)** below.

## Releasing from GitHub Actions

Two workflows, in `.github/workflows/`:

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `ci.yml` | push to `main`, pull requests | `swift build`, then the test suites one by one — the AppKit suites and the service tests fail when they share a process |
| `release.yml` | push to `main` | Picks the next version from the commits, creates the tag and the GitHub release with its notes, then runs `Scripts/archive-app.sh --upload` on a `macos-26` runner: archive, export, upload to App Store Connect |

There is no release command: a push to `main` is one. `Scripts/next-release.sh` reads the
Conventional Commits since the last `v*` tag and decides —

| Commits since the last tag | Bump | Example |
| --- | --- | --- |
| `type!:` or a `BREAKING CHANGE` footer | major | `1.1` → `2.0` |
| `feat` | minor | `1.1` → `1.2` |
| `fix`, `perf` | patch | `1.1` → `1.1.1` |
| only `docs`, `test`, `build`, `ci`, `refactor`, … | none | nothing happens |

Versions are written the way the store shows them — two components, a third only for a
patch. `Scripts/next-release.sh --notes` prints what goes on the GitHub release: breaking
changes, features, fixes, then the rest, one line per commit with its scope and hash. *Run
workflow* with a `version` input forces a version instead of deriving one.

The build number is the commit count on `main` (`git rev-list --count HEAD`) — App Store
Connect refuses any upload whose `CFBundleVersion` is not above the last one, whatever the
version, and the count only goes up. The store also closes a version once it is approved:
the next upload needs a higher `CFBundleShortVersionString`, which the bump rules give.
Nothing is attached to the GitHub release but the notes — the store is the only channel —
and the `.xcarchive` stays as a workflow artifact for two weeks, which is the build to launch
locally if a review comes back (the store-signed payload cannot be launched outside the store).

What the workflow does not do is submit: once Apple has processed the build, create the
version on App Store Connect, pick the build, paste the notes, and send it to review.

The runner has no Apple account, so everything Xcode would otherwise fetch is a repository
secret (Settings → Secrets and variables → Actions):

| Secret | Content |
| --- | --- |
| `APPLE_TEAM_ID` | The team identifier, as in `TEAM_ID` above |
| `APPLE_CERTIFICATES_P12` | A `.p12` exported from Keychain Access, base64-encoded (`base64 -i certs.p12 \| pbcopy`), holding **three** identities with their private keys: *Apple Development* (the archive is signed with it), *Apple Distribution* (the app in the package) and *Mac Installer Distribution* (the package itself). Select the three certificates in Keychain Access and export them together. Missing ones are created from Xcode → Settings → Accounts → Manage Certificates |
| `APPLE_CERTIFICATES_PASSWORD` | The password given at export |
| `ASC_KEY_ID`, `ASC_ISSUER_ID` | An App Store Connect API key with the **App Manager** role, and its issuer id |
| `ASC_API_KEY_P8` | The content of the `AuthKey_<id>.p8` file, as is |

The certificates land in a throwaway keychain that is deleted at the end of the job; the
provisioning profile is fetched by `-allowProvisioningUpdates` with the API key, so there is
no profile to export. If a certificate is missing from the `.p12`, Xcode creates one on the
team with `-allowProvisioningUpdates` — and its private key dies with the runner, so export
the real ones rather than let that happen.

## Screenshots

`Scripts/make-screenshots.sh` produces both sets — the store screenshots and the two README
previews — from the running app:

```bash
Scripts/make-screenshots.sh                # English and French, 2560×1600 and 1280×800
Scripts/make-screenshots.sh --all-sizes     # adds 1440×900 and 2880×1800
Scripts/make-screenshots.sh --capture-only  # just the raw window captures
```

Four shots per language, written to `docs/app-store/screenshots/<language>/<size>/`.

One thing the fourth shot says about this machine rather than about the app: under *Launch
at login*, the grey line reads "login item not found". `SMAppService.mainApp` reports
`.notFound` for any copy that has not been installed from a signed, provisioned build — that
is every locally built copy, whatever identity it is signed with, and the same line appears
in a `swift run` or a build directory launch. A copy installed from App Store Connect
reports `.notRegistered` instead, which is what a user sees. The pane itself, its controls
and their values are the app's.

What is captured and what is drawn matters, because the store's rules are about the first:
the composition is only there to give the app a screen to hang from.

| | |
| --- | --- |
| **Captured** | The panel and the preferences window, as windows — `screencapture -x -o -l <window number>`: alpha, no shadow, no desktop. The panel is drawn at its real size, 420 × 340 points, from a 2× capture, so what the store shows is the app's own pixels. |
| **Drawn** | The bezel, the wallpaper, the menu bar and the captions. A real capture of the menu bar would carry whatever the author had open; the status cluster is the app's own key glyph among the usual items, and nothing in the frame claims a feature the app does not have. |

Three things it needs: a Mac **with a notch** (the panel exists nowhere else — on an
external display the app is the menu bar icon and nothing more), an **unlocked** session
(`screencapture -l` cannot read another process's window while the screen is locked, and the
lock makes the app wipe its own codes), and the **Screen Recording** permission for whatever
runs the script.

The captures are driven by launch arguments that live behind `#if DEBUG`, next to the
`-confirm` harness described above:

| Argument | What it does |
| --- | --- |
| `-panel` | Opens the panel and holds it open: nobody is hovering the notch in a scripted run, and an unpinned panel collapses as soon as the pointer is seen elsewhere |
| `-settings` | Opens the preferences window; `-settings key` opens it on the YubiKey pane (the pane name is `SettingsTab`'s raw value) |
| `-confirm` | Opens the panel and asks for the first account — the confirmation sheet follows, and the demo's fake sensor answers 900 ms later |

Those 900 ms are the whole reason the captures are bursts: the sheet, and the code that
leaves the panel with its own window, are the states worth showing and the shortest-lived
ones. `Capture.swift` therefore writes every frame of a burst and a contact sheet beside them
(`build/screenshots/raw/contact-<state>-<language>.png`). The frames to keep are the
`framePicks` table at the top of `Compose.swift` — that table is the one thing to look at
after a re-run, since a slower or faster machine shifts which frame holds which state.

## Two things that decide whether it passes

**The reviewer has no YubiKey.** An app that answers "plug in your key" to the reviewer is
the classic rejection. The `-demo` argument swaps in a fake key and a fake sensor, and it is
compiled into the release build on purpose — say so in *Notes for Review*, with the exact
command the shipped build answers to:

> NotchOTP needs a YubiKey. To try it without one:
> `open -a NotchOTP --args -demo` — the panel then lists four demo accounts whose codes
> really rotate, and the fingerprint prompt is simulated. Hover the notch, click an
> account, and the confirmation sheet appears.

`-demo` is the **only** argument the release build answers to: `-confirm`, `-panel` and
`-settings` sit inside `#if DEBUG` in `AppController.applicationDidFinishLaunching`, and
`strings` on the archived release binary confirms they are absent. Useful as they are — one
command from launch to a revealed code — they are debug-only, so they must not appear in
anything the reviewer reads.

**The mark, in the metadata — not in the name.** "NotchOTP" contains no Yubico trademark,
and the 2.1 rejection confirms the name was not flagged. The exposure is elsewhere:
`yubikey` sits in the keyword field, and the fallback name *"NotchOTP: YubiKey codes"*
would put the mark in the app's title — never use it. Guideline 5.2.1 is enforced on
metadata, so keep the mark out of the name and the keyword field; naming the hardware in
the description to state a compatibility requirement is nominative use and is what the
review reply relies on.

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

## The listing

Everything App Store Connect asks for, ready to paste. The form itself: platform **macOS**,
bundle ID **app.notchotp**, SKU **notchotp**, Full Access, primary language **English**
(the app ships English and French; French is the development region).

**Name** — `NotchOTP` (fallback if taken: `NotchOTP: YubiKey codes`)

**Subtitle** (30 characters) — `YubiKey codes in the notch`

**Keywords** (100 characters) —
`yubikey,totp,hotp,2fa,otp,authenticator,oath,security key,menu bar,notch`

**Support URL** — `https://github.com/millianlmx/NotchOTP/issues`
**Marketing URL** — `https://github.com/millianlmx/NotchOTP`
**Privacy policy URL** — `https://github.com/millianlmx/NotchOTP/blob/main/docs/privacy.md`

**Category** — Utilities · **Price** — Free · **Age rating** — 4+ · **App Privacy** —
Data Not Collected

Where each of those lives matters, because App Store Connect reports a missing category on
the *version* page while the field sits elsewhere: the category, the age rating questionnaire
and the content rights declaration are all on **App Information** (General in the sidebar),
not on the version page. The version page carries what is localizable — description,
keywords, screenshots. `LSApplicationCategoryType` in `Info.plist` already says Utilities, so
pick the same thing here.

**Screenshots** — ready in `docs/app-store/screenshots/`, two sizes per language
(2560×1600 and 1280×800, both accepted; 1440×900 and 2880×1800 come out of the same script
with `--all-sizes`). Upload the English set under **English (U.S.)** and the French one
under **French**, four shots each:

| # | File | What it shows |
| --- | --- | --- |
| 1 | `01-codes-in-the-notch` | The panel open on the four demo accounts, every code still masked |
| 2 | `02-one-gesture-per-code` | The confirmation sheet, fingerprint prompt inside the panel |
| 3 | `03-the-code-in-the-clipboard` | A confirmed code on the list, and the clipboard countdown |
| 4 | `04-settings` | The preferences window, General pane |

The captions are English and French to match the listing the set is uploaded under.

**Promotional text** (170 characters) —

```
You don't pick a TOTP secret off the Mac. The key computes the code, you confirm with a
fingerprint, and it lands in the clipboard.
```

**Description** —

```
NotchOTP puts your one-time codes where you already look: the notch.

Hover it and the panel opens on your accounts. Click one, touch the sensor, and the code is
on your clipboard. The secrets never leave your YubiKey — the app stores nothing, syncs
nothing, and sends nothing.

ONE FINGERPRINT PER CODE
Every code asks for its own confirmation. Nothing is revealed by a stray click, and a code
you have shown once does not come back without a new gesture. Apple's own biometric prompt
is drawn inside the panel, never as a system alert floating somewhere else.

NOTHING LEAVES YOUR MAC
The codes are computed inside the YubiKey's OATH applet; the app receives the six- or
eight-digit result and nothing else. No account, no telemetry, no network connection at all.

BUILT FOR THE NOTCH
Collapsed, the panel draws nothing — the physical notch hides it entirely. It never steals
the keyboard, and it leaves no icon in the Dock.

ALSO
• Add accounts by typing, by pasting an otpauth:// link, or by scanning a QR code on screen
• TOTP and HOTP, 6 or 8 digits, 30 or 60 second periods, touch-required credentials
• Search, keyboard navigation, rename and delete without leaving the panel
• Lock wipes the revealed codes and relocks the key's applet
• The clipboard is wiped after the delay you choose, and only if it still holds the code
• Macs without Touch ID confirm with a press and hold instead

REQUIREMENTS
• A Mac with a notch (elsewhere only the menu bar icon is available)
• macOS 14 or later
• A YubiKey with OATH credentials already stored
• Touch ID, an Apple Watch, or the press-and-hold mode, to confirm

No YubiKey at hand? Launch it with -demo to see the panel with four demo accounts.
```

**Notes for Review** — this is the text of record for every submission: it is the same
information the 2.1 reply carries, and Apple asks for it to stay in the Notes field.

```
NotchOTP shows one-time passcodes (TOTP/HOTP) computed by a YubiKey's OATH applet, from the
Mac's notch. Purpose: keep the codes where the user already looks, with the secret never
leaving the key. Audience: individual Mac users who already own a YubiKey with OATH
credentials stored on it. It is free, has no account, no user-generated content, no paid
content or in-app purchase, and no network access of any kind.

REVIEWER WITHOUT A YUBIKEY — the build carries a demonstration mode, on purpose:

    open -a NotchOTP --args -demo

The panel then lists four demonstration accounts whose codes really rotate, and the
fingerprint prompt is simulated (the fake sensor answers about 900 ms after the confirmation
starts): hover the notch, click an account, and the sheet appears. `-demo` is the only launch
argument the submitted build answers to. With a YubiKey plugged in, the same flow runs against
the real key: list the credentials, show the confirmation sheet, wait for a fingerprint, copy
the code. The app is sandboxed with com.apple.security.smartcard and talks to the key through
the system's PC/SC service. Everything the app does is logged to the unified log under the
app.notchotp subsystem.

EXTERNAL SERVICES — none. No server, no data provider, no authentication or payment service,
no analytics, no crash reporting, no update check. Locally it uses the YubiKey over PC/SC,
Apple's LocalAuthentication (LocalAuthenticationEmbeddedUI for the in-panel prompt),
ScreenCaptureKit + Vision only for the user-initiated "Scan the screen", Screen Recording
permission being asked by macOS, ServiceManagement for "Launch at login" and Security for the
optional OATH password in the keychain. The only third-party code is YubiKit
(github.com/Yubico/yubikit-swift, Apache-2.0), statically linked, licensed alongside the app.

REGIONS — no differences; identical in every storefront, shipped in English and French, no
region-restricted feature and nothing that could vary since there is no network.

REGULATED INDUSTRY — none. The app is a local client for a hardware authenticator the user
provisioned themselves; it operates no service, holds no user data and performs no
transaction. No third-party material is bundled. "YubiKey" is named only to state hardware
compatibility; the app is not affiliated with or endorsed by Yubico. Query the store listing
for a third-party mark before reusing this paragraph.
```

## Guideline 2.1 — the information request

The first submission was rejected under **2.1 (Information Needed — New App Submission)**,
the generic request sent to accounts with little review history. It points at no defect: it
asks for a screen recording plus five written answers, and lists the usual traps underneath
(3.1.1 in-app purchase, 3.2 business distribution) that do not apply here — the app is free,
has no IAP, and is aimed at individuals.

Where the answer goes: **App Store Connect → the rejected version → App Review Information →
Notes**, and the same text as the reply in **Resolution Center**, with the recording attached.

### The screen recording

Scripted: `Scripts/record-review-video.sh` drives the whole take with synthetic pointer and
keyboard events, and records it.

```bash
Scripts/record-review-video.sh --demo                    # unattended, simulated sensor
Scripts/record-review-video.sh --key --finger-wait 60    # real key: touch the sensor
Scripts/record-review-video.sh --demo --print-geometry   # where each target lands
Scripts/record-review-video.sh --demo --dry-run          # events only, no recording
```

It needs the **Accessibility** permission for whatever runs it — without it the kernel drops
the posted events silently and the take is a minute of nothing happening — and **Screen
Recording** for the capture. `Scripts/Review/Recorder.swift` holds the gestures and the
arithmetic: it derives every coordinate from the app's own constants (`NotchGeometry`'s
420 × 340 panel, `PanelStyle`'s 44 pt header and 48 pt rows) rather than from measured
pixels, so it survives a re-run on a different Mac.

It runs the **archived** build, not `build/NotchOTP.app`: the app under test has to be the
one that was submitted, and the store-signed payload cannot be launched outside the store
path (launchd spawn failure 163). The archive the export came from is the same Release
configuration, sandboxed, universal.

The take, in order — the shape the reply describes, so the two must be kept in step:

1. Launch. The menu bar icon appears; no Dock icon, no window.
2. Hover the notch → the panel opens; the accounts are listed, codes masked.
3. Search: the magnifier, then typing filters the list.
4. Click an account → the confirmation sheet, issuer, account and masked code.
5. Confirm — Touch ID on a real key, the simulated sensor on `--demo` — and the code is
   revealed and copied; the clipboard countdown shows in the footer.
6. Paste it into TextEdit to prove the clipboard really holds it.
7. Settings, from the gear.
8. Right-click a row → rename, delete.
9. Lock, then leave the notch: the revealed codes are gone and the applet is relocked.

`--demo` is the unattended take and the one to use when no key is at hand; say so in the
reply. `--key` is the stronger recording — the reviewer says they test on real hardware —
and the only one that needs a human: the driver waits `--finger-wait` seconds for the finger.

Two traps the first takes walked into, worth not repeating:

- **Do not pipe the take.** `./Scripts/record-review-video.sh --demo | head -20` kills the
  recorder the moment `head` exits, and the run stops half way with the video file never
  written. Redirect to a file instead.
- **The paste is the only step that can touch the user's machine.** TextEdit autosaves
  *untitled* documents into the user's iCloud folder, and ⌘Q never gets past the save sheet
  ⌘W raises — three takes left three documents and three running instances behind. The
  driver now pastes into a scratch file in the temporary directory and kills the instance it
  started, with no other TextEdit ever in the set.

Manual fallback, if the permission is refused:

```bash
screencapture -v -C -k -g -V 120 ~/Desktop/NotchOTP-2.1-review.mov
# -v video  -V seconds  -C cursor  -k show clicks  -g microphone
```

QuickTime Player (File → New Screen Recording, with the microphone) is the fallback when
`screencapture` is refused. Keep it under a minute and under ~100 MB; a YouTube or Vimeo link
may be pasted into the reply instead of an attachment.

### The reply

Addresses the six numbered points in the order asked. Replace the bracketed parts before
sending; keep the rest as is.

```
Hello, and thank you for the review.

Below is the information requested in the Guideline 2.1 note. The same text has been added to
the Notes field of the App Review Information section.

One point answers several of your questions at once: NotchOTP is a fully local macOS utility.
It has no user account, no login, and therefore no account deletion; no user-generated
content; and no paid content, subscriptions or in-app purchases — none of the three flows
listed in your note exists in this app. It also contains no networking code whatsoever: no
server, no analytics, no crash reporting, no update check.

1. SCREEN RECORDING
Attached: NotchOTP-2.1-review.mov (50 MB, 36.6 seconds), captured on a physical MacBook Pro
16-inch (Apple M4 Pro) running macOS 27.0 (26A428), on the build submitted for this review —
version 1.0, build 1 (universal: arm64 and x86_64).

It was recorded in the demonstration mode built into the submitted build, because this app
computes its codes inside a YubiKey and no key was at hand on the recording machine — the
panel header reads "YubiKey 5.7.4 (demo)". That mode computes real TOTP codes locally and
replaces the hardware only: with a YubiKey plugged in, the very same flow runs against it and
the panel lists the credentials stored on the key.

The recording opens on the launch of the app — no window, no Dock icon, only the menu bar
item — and follows the typical user flow: launching from Applications; hovering the notch to
open the panel on the accounts, every code masked; searching the list; clicking an account to
open the confirmation sheet; confirming, after which the code is revealed and copied to the
clipboard; pasting it into a text editor to show that the clipboard really holds it; the
Settings window; right-clicking a row for rename and delete; and the lock that wipes the
revealed codes when the panel is left. It is unedited apart from trimming the head and tail.

2. PURPOSE AND TARGET AUDIENCE
NotchOTP displays one-time passcodes (TOTP and HOTP) computed by a YubiKey's OATH applet, from
the notch of the Mac.
The problem it solves: on macOS the TOTP secret normally lives in software — an authenticator
app's database or the keychain — where it can be copied, backed up or synced, and the codes
are shown in a window the user has to keep open or switch to. Users who already own a hardware
security key have no native, comfortable way to read the codes stored on it.
The value it provides: the codes appear where the user already looks; the secret never leaves
the key; the app stores nothing and syncs nothing; and each individual code requires its own
deliberate confirmation — Touch ID, an Apple Watch double-click, or press-and-hold — so a
stray click reveals nothing, unlike a list that shows every code at once.
Target audience: individual Mac users who already own a YubiKey and have stored OATH
credentials on it, provisioned beforehand with Yubico Authenticator or `ykman oath accounts
add`. It is a personal utility, not a product for businesses or organisations. It is free of
charge, with no in-app purchase.

3. SETUP AND ACCESS
There is no account, no login and no credential of any kind: there is nothing to sign in to,
and no demo account to provide.
Requirements: macOS 14 or later; a Mac with a notch for the panel (on other Macs the app is
its menu bar icon, which opens the same panel); a YubiKey that already holds OATH credentials;
and Touch ID or a paired Apple Watch — or the "press and hold" confirmation mode, on Macs
without a biometric sensor.
Main features, and how to reach them: hovering the notch opens the panel with the accounts
stored on the key; clicking an account opens the confirmation sheet; authenticating reveals the
code and copies it. Command-F (or the magnifier) searches the list; the arrow keys and Return
navigate and confirm; right-clicking a row renames or deletes a credential, deletion asking
for a second confirmation inside the panel. The "+" button in the panel header adds an account
— typed, pasted as an otpauth:// link, or read from a QR code on screen through "Scan the
screen". The gear icon opens Settings (General, YubiKey, About).
Because this app requires a YubiKey, the submitted build carries a demonstration mode,
compiled into the release build on purpose for exactly this situation. No hardware is needed:

    open -a NotchOTP --args -demo

The panel then lists four demonstration accounts whose codes really rotate (standard TOTP
computed locally by CryptoKit), and the fingerprint prompt is simulated, answering about 900 ms
after the confirmation starts. Hover the notch, click an account, and the sheet appears.

No sample files are required.

4. EXTERNAL SERVICES, TOOLS OR PLATFORMS
None. The app does not make a single network request, so it uses no data provider, no
authentication service, no payment processor and no AI service. Its core functionality is
delivered by local components only: the user's own YubiKey, reached through the macOS smart
card service (PC/SC) — the app is sandboxed with the com.apple.security.smartcard entitlement
and speaks to the system's PC/SC service rather than to the USB device; Apple's
LocalAuthentication, with LocalAuthenticationEmbeddedUI for the prompt drawn inside the panel;
ScreenCaptureKit with Vision, used only when the user chooses "Scan the screen" and only for
the rectangle they drag, with the Screen Recording permission macOS asks for; ServiceManagement
for "Launch at login"; and the Security framework for the optional OATH password, stored in the
keychain only if the user ticks the box. The only third-party code is YubiKit
(https://github.com/Yubico/yubikit-swift, Apache-2.0), a library that speaks to the key over
PC/SC — statically linked, no networking, its licence shipped with the app.

5. REGIONAL DIFFERENCES
There are none. The app is identical in every region and storefront; it ships in English and
French and follows the Mac's language; there is no region-restricted feature, no geo-restriction
and no localised content difference. Since the app never contacts the network, nothing about it
can vary by region.

6. REGULATED INDUSTRY AND THIRD-PARTY MATERIAL
None applies. The app does not provide a regulated service — authentication, financial, health
or gambling. It is a local client for a hardware authenticator that the user has provisioned
themselves and that already holds the credentials; it operates no service, holds no user data
and performs no transaction. No protected third-party material is bundled: no third-party logos,
artwork, fonts or datasets. The name of the hardware — YubiKey — is used descriptively, to state
which device the app is compatible with; the app is not affiliated with, sponsored or endorsed
by Yubico. The only cryptography is standard HMAC and PBKDF2 on the local device with no
network, declared as non-exempt encryption = NO in the Info.plist.

Please let me know if any further detail would help. Thank you.
```

### Afterwards

- The Notes field keeps this information for future submissions; the block above is the source
  of truth for it, so edit here and re-paste.
- Watch the two metadata items before re-submitting: `yubikey` out of the keyword field, and
  never the fallback name *"NotchOTP: YubiKey codes"*.
- Also confirm the reviewer-facing `-demo` path still works on whatever build is resubmitted:
  the demo is compiled into release on purpose, and a `#if DEBUG` guard around it would make
  the reviewer see nothing but "plug in your key".
