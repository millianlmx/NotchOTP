# Launch thread

Attach `video/out/notchotp.mp4` (16:9) to tweet 1. `video/out/notchotp-square.mp4` is the
same cut at 1:1 for feeds that crop. Every tweet is under 280 characters; the counts are
in the margin so an edit does not silently break one.

---

**1/** *(video)*

Your YubiKey holds your 2FA codes. Your Mac has a notch. I wired the two together.

NotchOTP: hover the notch, pick an account, touch the sensor — the code is on your clipboard.

No window. No Dock icon. Nothing stored on the Mac.

🧵 *(233)*

**2/**

Why: Yubico's own app is a full window you open, find, click through and close for a six-digit number you need 20 times a day.

The notch is already there, already in the middle of the screen, and draws nothing when it's not in use. That's where a code picker belongs. *(268)*

**3/**

Where the codes come from: your YubiKey computes TOTP/HOTP inside its OATH applet. NotchOTP only receives the result.

No secret on disk. No sync. No online account. Unplug the key and there is nothing left to steal. *(216)*

**4/**

One gesture, one code — Apple Pay's mechanic, transposed.

The panel lists your accounts like Wallet lists cards. Every code asks for its own fingerprint (or Apple Watch double-click). Apple's biometric prompt is drawn *inside* the panel, not in a system alert somewhere else. *(274)*

**5/**

The bug that cost me the most: `LAContext` remembers.

A context that has already matched a finger answers the next evaluation in ~10 ms, no new touch. One fingerprint was silently opening every code after it.

Now each confirmation gets a fresh context. Measured: 1.4 s per code. *(278)*

**6/**

It doesn't lie about what it reads.

Opening the panel asks the key for *names* only. A code is computed only after your gesture, for that one account, and it disappears with its own validity window. There is a test for it: no code request reaches the key before the gesture. *(273)*

**7/**

The rest, because it still has to be a real app:

⌘F search · add accounts by typing, pasting an otpauth:// link, or scanning a QR code on screen · rename / delete · OATH password · lock on sleep, screen lock or unplug · clipboard wiped after a delay you pick. *(260)*

**8/**

No Touch ID? Press and hold.

Hold the target for about a second, the ring fills, the code arrives. Same guarantee: one deliberate gesture per code, no sensor involved. *(168)*

**9/**

Small on purpose: 2.1 MB, two SwiftPM targets, one dependency (Yubico's own YubiKit).

Source is on GitHub under PolyForm Noncommercial — clone it and build it for free. The signed, sandboxed build is $2.99 on the Mac App Store. No tiers, no telemetry, no account. *(264)*

**10/**

Fun fact: App Review asked for a video shot on real hardware. I didn't film it — a Swift script drives the panel with synthetic input, derived from the app's own layout constants.

The video in tweet 1 is the same script, cut with Remotion. Both are in the repo. *(262)*

**11/**

Needs: a Mac with a notch, macOS 14+, a USB-C YubiKey with OATH accounts on it. English and French.

Mac App Store → https://apps.apple.com/app/id6812282307
Source → https://github.com/millianlmx/NotchOTP

Questions welcome — I read every reply. *(245)*

**12/** *(reply to tweet 1 — the licence requires this credit alongside the video)*

🎵 Sun And Clouds by | e s c p | https://www.escp.space
https://escp-music.bandcamp.com *(86)*

---

## Notes for posting

- Tweet 2 states the positioning; keep it factual, don't name-call Yubico beyond "a full window".
- The LAContext story (5) and the App Review script (10) are the two tweets people share; keep them even if the thread is shortened.
- Shortest viable thread: 1, 3, 4, 5, 11 — plus 12, always: it is the music credit.
- Music: "Sun And Clouds", FSM Team feat. < e s c p >, CC BY 4.0, from
  https://www.free-stock-music.com/sun-and-clouds.html. The page asks for the credit line in
  tweet 12 verbatim ("copy & paste"); the $8 Bandcamp licence waives it if you would rather
  not have a credit under the launch video.

## Calendar

One thread, posted in one go; the standalone posts are what actually travel on X — a reply
inside a thread reaches a fraction of what a top-level post does. Tuesday to Thursday,
15:00–17:00 Paris: US East is mid-morning, US West is waking up, Europe is still at work.

| When | What | Video |
| --- | --- | --- |
| D−2, 16:00 | Teaser, top-level: *"Shipping something for YubiKey owners with a notch on Thursday."* + one still (`docs/panel-list.png`) | none — keep the video for launch |
| D0, 15:30 | The thread, tweets 1–12. Pin tweet 1. | `notchotp.mp4` on **tweet 1 only** (X recompresses; one video per thread) |
| D0, all afternoon | Reply to every reply within the hour; the algorithm counts replies-to-replies | — |
| D+1, 16:00 | Standalone A (below) — the LAContext bug, no link in the body, link in a reply | `notchotp-square.mp4` in the reply with the link |
| D+3, 16:00 | Standalone B — the App Review video was scripted; link to the repo in a reply | 6 s clip of the panel opening if there is one, else the still |
| D+5 | Show HN: "NotchOTP – YubiKey OATH codes in the MacBook notch" → GitHub repo, not the App Store. Plain text, 2 sentences, no adjectives. Post 14:00 Paris (08:00 ET). | HN ignores video |
| D+7 | r/yubikey, r/macapps, r/MacOS: same text as HN, the square video embedded natively | `notchotp-square.mp4` |
| D+14 | Standalone C — what people asked in the replies, answered, and the first update if there is one | — |

Before D0: the README still says the app "is not there yet" on the App Store; fix it, the
thread links the repo.

### Show HN (D+5)

Hacker News (news.ycombinator.com) is the forum of Y Combinator: developers, founders, and
the people who own a YubiKey. "Show HN" is its section for things you made; a post that
reaches the front page brings thousands of exactly the right readers in a day. Account
needed (free, no karma required to post). Steps:

1. https://news.ycombinator.com/submit — fill **title** and **url** only, leave **text** empty
   (a Show HN with both is penalised).
2. Title, verbatim: `Show HN: NotchOTP – YubiKey OATH codes in the MacBook notch`
3. URL: `https://github.com/millianlmx/NotchOTP` — the repo, not the App Store: HN wants
   something to read and build, and the README is the pitch.
4. Post at 14:00 Paris (08:00 New York), Tuesday to Thursday.
5. Immediately add the first comment yourself, plain and short:

   > I built this because the official Yubico Authenticator is a full window for a six-digit
   > number. The panel lives in the notch, every code asks for its own Touch ID, and the
   > secrets never leave the key. The App Store build is $2.99; the source is PolyForm
   > Noncommercial and builds with one script. Happy to answer anything about the OATH
   > applet or the LAContext reuse bug (one fingerprint was silently unlocking every code).

6. Stay on the thread for four hours. Answer every question with facts; never argue, never
   ask for upvotes (it gets the post killed). Criticism of the price or the licence will
   come — answer once, calmly, move on.

### Reddit (D+7)

Reddit is a set of forums ("subreddits") with their own rules and moderators. Account needed;
a brand-new account posting a link gets removed as spam, so create it now, comment in
r/yubikey a few times before D+7, and read each subreddit's rules in its sidebar first.

| Subreddit | Why | Rule to check |
| --- | --- | --- |
| r/yubikey | the exact audience; small, every owner reads it | self-promotion is tolerated when it is a real tool and you answer questions |
| r/macapps | people who collect Mac utilities; a video post does well | "Dev post" flair, one post per app |
| r/MacOS | large, general | self-promo only on allowed days — check |

One post per subreddit, a day apart, not three at once. Use a **video post** with
`video/out/notchotp-square.mp4` uploaded natively (not a link to X). Title:

`NotchOTP — your YubiKey's 2FA codes in the MacBook notch, one Touch ID per code`

First comment, same as HN plus the links (App Store and GitHub), and the credit line for
the music is not needed there (only required next to the video on the platform where it
plays — add it anyway at the end of the comment, it costs one line).

Both: the goal is not upvotes, it is the questions. Write them down; they are Standalone C
and the next README section.

### Standalone A (D+1)

Found a Touch ID bug that would have made my 2FA app lie.

An LAContext that has already matched a finger answers the next evaluatePolicy in ~10 ms, no touch. One fingerprint was silently unlocking every code after it.

Fix: a fresh context per confirmation. 1.4 s per code now. *(278)*

### Standalone B (D+3)

App Review asked for a video "recorded on physical hardware" before approving NotchOTP.

I didn't film it. A Swift script drives the panel with synthetic input, each click derived from the app's layout constants, and checks via the AX API that the panel is open first.

Approved. *(279)*

### Standalone C (D+14)

Written on the day, from the replies.

## YubiKey affiliation

**No.** Decided 14/10/2026: the reach is not there for it to be worth anything.

- Yubico retired its own programme in 2017 and points affiliates at Amazon Associates;
  "PC & components" pays ~2.5 % (~1.40 € per 5C NFC), and Amazon closes the account after
  180 days without three sales — which a small X account would hit.
- The one thing worth keeping from the idea is the content, without the link: a plain
  "which key do I buy" line (USB-C, firmware 5.x, 5C NFC or 5C Nano) in the README and
  as a reply when someone asks. It answers the question and keeps "sells nothing" true.
- Revisit only if a channel brings real traffic (HN front page, a newsletter); then on the
  website or README with the Amazon disclosure line, never inside the app.
