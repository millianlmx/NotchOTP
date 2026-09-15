# Privacy policy

NotchOTP runs entirely on your Mac. It has no account, no server, and no telemetry: the app
never opens a network connection, so there is nothing to send anywhere and nobody to send it
to.

## What the app reads

- **Your YubiKey.** The one-time codes are computed inside the key's OATH applet and handed
  back as a six- or eight-digit code. The secret they are derived from never leaves the key.
- **The account names stored on the key** — issuer and account, so the panel can list them.
- **Your fingerprint**, through Apple's LocalAuthentication, when you confirm a code. The
  check happens on your Mac, by macOS; the app only learns whether it succeeded.
- **The screen**, only when you press *Scan the screen* to read a QR code, and only for the
  rectangle you drag. macOS asks for the Screen Recording permission first.

## What the app stores

- **Nothing about you.** No analytics, no identifiers, no usage history.
- **Nothing about your codes.** A code lives in memory until its validity window ends, and
  in the clipboard until the delay you chose in the settings — and the clipboard is only
  cleared if the code is still the thing in it.
- **The OATH password, if you ask it to.** Only when your key's OATH applet is
  password-protected and you tick "remember in the keychain": it goes into your login
  keychain, on your Mac, and is used for one thing — opening the applet. Untick the box and
  it is removed.

## What leaves your Mac

Nothing. There is no analytics SDK, no crash reporter, no update check, no font or asset
fetch. The only links in the app are to System Settings panes on your own machine.

## Children, tracking, advertising

None of it applies: the app has no advertising, no tracking, and no third-party code beyond
[YubiKit](https://github.com/Yubico/yubikit-swift), which talks to the key over the smart card
service.

## Questions

Open an issue on <https://github.com/millianlmx/NotchOTP/issues>.
