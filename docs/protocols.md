# Protocols

What the app sends to the key, what it gets back, and what it refuses to swallow.

## What lives on the key

A YubiKey exposes an **OATH applet**: a small database of credentials, each one a secret plus
metadata.

| Field | Role |
| --- | --- |
| id | the credential's identifier on the key. Yubico derives it from the issuer and the name: renaming an account **changes its id** |
| issuer / name | the label. This is all the app reads without authorization |
| type | TOTP (period 30 or 60 s) or HOTP (counter) |
| algorithm | SHA-1, SHA-256 or SHA-512 |
| digits | 6 or 8 |
| requiresTouch | the key will demand a physical touch to compute this code |

The secret never leaves the key: the key computes, the app receives a code of six or eight
digits.

## The transport

The YubiKey presents itself as a **smart card reader** (`system_profiler
SPSmartCardsDataType` lists it under "Yubico YubiKey OTP+FIDO+CCID"). macOS exposes it through
`TKSmartCardSlotManager`; YubiKit opens a `USBSmartCardConnection` and then selects the OATH
applet (`OATHSession.makeSession`). Everything else is TLV over APDU.

One thing to watch: if `TKSmartCardSlotManager.default` is `nil` — no key plugged in, or a
process without the smart card entitlement — YubiKit hits an `assertionFailure` (a trap in
debug builds) before throwing an error about an unsupported key model, which sends you down
the wrong path. So `USBYubiKeyConnector.connect()` tests the slot manager **before** calling
YubiKit, and throws `OATHFailure.readerUnavailable`, which the service treats as the resting
state (no error banner).

## The commands

| Operation | CLA | INS | P1 / P2 | Data |
| --- | --- | --- | --- | --- |
| List credentials | 0x00 | **0xa1** | 0 / 0 | — |
| Compute a code | 0x00 | **0xa2** | 0 / **0x01** | TLV name (0x71) + challenge (0x74) |
| Compute an HMAC response | 0x00 | 0xa2 | 0 / 0 | TLV name + challenge |
| Add a credential | 0x00 | 0x01 | 0 / 0 | credential TLV |
| Delete | 0x00 | 0x02 | 0 / 0 | TLV name (0x71) |
| Set the password | 0x00 | 0x03 | 0 / 0 | key + challenge + response |
| Reset the applet | 0x00 | 0x04 | 0xde / 0xad | — |
| Rename | 0x00 | 0x05 | 0 / 0 | TLV name + issuer |

**0xa1 is the command that counts**: it lists the credentials **without computing a single
code**. It is what makes the "no code without authorization" model possible — and the reason
YubicoNotch never uses `calculateCredentialCodes()`, which would compute everything at once.

## Computing a code

`0xa2` with P2 = 1, in two TLVs:

```
name (0x71): the credential's identifier
challenge (0x74):
    TOTP → unix_time / period, as big-endian UInt64
    HOTP → empty (the key increments its counter)
```

Response: one TLV (0x75) whose **first byte is the number of digits**, followed by the
truncated code as a big-endian UInt32, which the key has already formatted for that number of
digits.

The key **has no clock**: the app is the one that passes the timestamp. TOTP windows are
therefore aligned on the epoch, which makes it possible to show an accurate countdown without
ever having computed the code (`CodeClock.window(period:now:)`).

A `requiresTouch` credential makes the command wait until the physical touch: that is the
`reading` phase, which the interface announces with "Touch the key".

## The applet password

The OATH applet can be protected. The password never travels as such: it is derived by
**PBKDF2** into an access key, and command `0x03` exchanges a challenge/response. As long as
the applet is closed, every read answers `securityConditionNotSatisfied`, which the app maps
to `OATHFailure.passwordRequired`.

YubicoNotch stores the **password** (not the derived key) in the session keychain, and
replays it to reopen the applet. The biometry-protected keychain
(`SecAccessControl` + `kSecUseDataProtectionKeychain`) is not usable here: it requires an app
signed with a profile and returns `errSecMissingEntitlement` (-34018) on an ad hoc signature.
Assumed trade-off, and documented: that password alone is useless without the physical key.

## `otpauth://`

The standard authenticator URI:

```
otpauth://totp/Issuer:account?secret=BASE32&issuer=Issuer&algorithm=SHA1&digits=6&period=30
otpauth://hotp/account?secret=BASE32&counter=0
```

YubicoNotch's parsing (`NewCredential.parse`) is **written by hand, without `URLComponents`**:
re-encoding a secret breaks it, and a URI can arrive from an imperfect QR code.

- in the *query*, `+` decodes as a space (never valid in base32); in the *label* (the path),
  `+` stays literal;
- the issuer and the account split on the **raw `:` before any decoding**: a `%3A` therefore
  stays data, not a separator;
- the validation order is: scheme → host (`totp`/`hotp`, otherwise `unsupportedType`) →
  secret → algorithm → digits → period/counter → name. An unknown type therefore wins over an
  invalid secret, and the message says so;
- `requiresTouch` is always `false` at parsing time (that is set in the form), and the default
  algorithm is SHA-1;
- the "at least 10 bytes of secret" guard only exists in `fromForm` (manual entry), not in
  `parse`: a QR code that declares a short secret is accepted as is.

## Base32

An in-house RFC 4648 decoder (`Core/Base32.swift`), case-insensitive, which ignores spaces,
line breaks and dashes — secrets are often copied in groups:

- a padding, when present, must **close a group of 8**: `MZXW6===` passes, `MZXW6=` returns
  `nil` even if the residual bits are zero;
- after extracting the bytes, 0 to 4 residual bits must remain, **and they must be zero**:
  `MZXW7` returns `nil`;
- an empty input gives an empty `Data()`. The callers are the ones that reject: `fromForm`
  requires at least 10 bytes, because a shorter secret is not a secret.

## What the app sees, at every instant

| Moment | What the app has in hand |
| --- | --- |
| panel closed | nothing: the key is not polled |
| panel open | the account names (applet open) — no code |
| confirmation in progress | nothing more |
| after the gesture | **one** code, the confirmed account's, and it disappears at the end of its window |
| locked | nothing: the session is closed, the list is wiped |

The clipboard is wiped after the chosen delay, and only if the copied code is still there —
text copied in the meantime is never touched.
