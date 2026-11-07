# Paperplane iOS spike (THE-203)

Throwaway spike for THE-203. It checks the auth flow and the Liquid Glass
wrapper on a real iPhone. It is not product code. Do not merge it.

## What it does

- **Auth tab:** password-first login
  (`/api/auth/sign-in/email` -> `/api/board-api-keys` -> `/api/cli-auth/me` ->
  sign-out) and device login (challenge -> Safari approval -> poll every 3 s ->
  `/api/cli-auth/me`).
- **Glass tab:** glass tab bar, card, and sheet. A toggle forces the solid
  fallback through `GlassAccessibilityScope`.
- **Checks tab:** the iPhone checklist.

Client rules used in the spike:

- `Origin` is the base URL on every mutation (sign-in, mint, sign-out).
- Sign-in `429` reads `X-Retry-After` (the client also reads `Retry-After`).
- Device login keeps the `boardApiToken` from challenge creation.
- The poll path gets the `/api` prefix and obeys `Retry-After` on `429`.
- The password and board key live in memory only. Nothing is written to disk.

## Requirements

- macOS with Xcode. Free Apple ID signing is enough.
- Flutter 3.41 or newer on `PATH`.
- An iPhone with Developer Mode on and a USB cable.
- A Paperclip test instance in `authenticated` mode and a temporary test
  account. Do not use production credentials.

## One command

```sh
./tool/run_ios.sh
```

The script runs `flutter pub get`, finds the first physical iPhone or iPad, and
starts `flutter run`. If more than one device is attached, set
`IOS_DEVICE_ID=<id>` (see `flutter devices`).

For frame times, use profile mode:

```sh
./tool/run_ios.sh --profile
```

### One-time signing setup

The first run needs a signing team. If none is set, the script stops and prints
these steps:

1. `open ios/Runner.xcworkspace`
2. Select the **Runner** target -> **Signing & Capabilities**.
3. Choose your **Personal Team** and keep **Automatically manage signing** on.
4. Run `./tool/run_ios.sh` again.

The bundle id is `com.theskilllab.paperplane.spike`. Free provisioning creates
the profile.

## iPhone checks, in order

1. **Launch.** The glass tab bar shows three tabs. The gradient is visible
   through the bar.
2. **Local Network prompt.** Enter a LAN address on the Auth tab and tap
   `Health + LAN prompt`. Allow the iOS Local Network prompt. Expect `200`.
3. **Password-first.** Enter the test account. Tap `Password-first login`.
   Expect: sign-in `200`, mint `201`, a redacted key shape, `/cli-auth/me`
   `200`, sign-out `200`. A `403` at mint is the Origin guard; record it.
4. **Device login.** Tap `Device login (Safari)`. Safari opens the approval
   page. Sign in there and approve. Return to the app. Expect the poll to move
   to `approved`, then `/cli-auth/me` `200`. If the poll returns `429`, the app
   waits for `Retry-After` and logs the wait.
5. **Glass sheet.** On the Glass tab, tap `Open glass sheet`. The panel must be
   readable and the background must blur.
6. **Reduce Transparency.** iOS Settings -> Accessibility -> Display & Text
   Size -> Reduce Transparency. Record whether the glass becomes solid. The
   package maps this setting to Increase Contrast, so record the result as
   observed.
7. **Increase Contrast.** Same menu. Expect the solid fallback. Record it.
8. **Frame times.** Run `./tool/run_ios.sh --profile`. Turn on the Performance
   overlay. Switch tabs, scroll both tabs, and open the sheet. Record the frame
   times and any jank.

## Results to send back

Paste the table and the **redacted log** from the Auth tab. The `Copy` button
removes the base URL, the email, the password, and key values.

| Check | Result | Notes |
|---|---|---|
| Launch + glass tab bar | | |
| Local Network prompt + health | | |
| Password-first (a)-(d) | | |
| Device login via Safari | | |
| Glass sheet | | |
| Reduce Transparency | | |
| Increase Contrast | | |
| Profile frame times | | |
| Android frame times | not tested | No Android device; emulator is not a 60 fps gate |

Do not paste a real instance URL, password, or key into Paperclip.

## Android

Android frame times are **not tested**. No Android device is available. An
emulator is not a substitute for the 60 fps gate. The Android project is kept
buildable only as a compile check.

## Why these dependencies

- `liquid_glass_widgets: 1.17.0` is the exact package and version under test.
- `url_launcher: 6.3.3` opens the approval page in the external browser
  (Safari), which is the device-login flow under test.

Both are spike-only. Do not copy them into the app without the ADR gate.
