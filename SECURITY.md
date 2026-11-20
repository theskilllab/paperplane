# Security policy

## Report a vulnerability

Use GitHub's **private vulnerability reporting**: open the repository's
**Security** tab and choose **Report a vulnerability**. Please do not open a
public issue or pull request for a vulnerability, and never paste tokens,
board keys or private server URLs anywhere public.

We will acknowledge a report as soon as we can and keep you updated until it
is fixed.

## What Paperplane holds

Paperplane signs in to a self-hosted Paperclip server and stores a **board
API key** in the device's secure storage.

**A board key has the full power of the user who created it.** Anyone holding
the key can do in Paperclip whatever that user can do, across every
organization the user can access. Treat it like a password. If a key may have
leaked, revoke it in Paperclip and sign in again.

The app asks the server for a key that expires after 30 days and never for a
key without an expiry. A key you paste in yourself has no known expiry, because
the app did not create it. The app still replaces any key it holds after seven
days of use, provided the server accepts it; the replacement then expires after
30 days. Signing out revokes the key on the server before it is deleted from
the device.

Rotation is silent and never asks for the password. The app asks the server for
the replacement while the old key still works, stores the replacement on the
device first, and only then revokes the old key. If minting or storing the
replacement fails, the old key stays in use until it expires. The app checks at
start and while it is in the foreground.

The app records whether it created a key or you pasted it in, and only revokes
a key it created. A pasted key may also be in use by another client, so after a
rotation the app keeps the pasted key valid and lets it expire on its own. A
key stored by an older app version has no recorded origin, so it is treated the
same way and is not revoked automatically. That older key also starts its
seven-day clock at the first launch after the upgrade, so its first rotation
can be deferred by up to seven days; a key that is already close to expiry can
expire first and send you to sign-in.

A secure-storage write can fail after the platform has already committed it. On
a write error the app reads the entry back before deciding anything. If it can
read the entry, it acts on what is actually stored. If it cannot read the entry,
it does not revoke the replacement, because that replacement may be the live
key; it is left to expire after 30 days instead. The same rule covers cleanup:
if a rotation is abandoned and the app cannot prove that the replacement was
removed from the device, it does not revoke it. The valid key stays recoverable
and a following sign-out tries to remove it again, rather than leaving a
revoked key stored as if the user were still signed in. If a sign-out cannot
prove that the device key was removed, the app records the sign-out as
incomplete: it does not restore that key at the next start, it shows that the
sign-out is incomplete, and it retries the removal. Signing in again replaces
the key. Secure-storage changes for one server are serialized in the app so a
delayed rotation cannot overwrite or delete a newer sign-in's key.

Paperplane also keeps the last company list and Inbox feed in the app's
preferences, so a cold start without network can show the last feed. They
contain titles and item metadata, not the key, and are deleted on sign-out
and on an expired session. On iOS, a key can outlive an app reinstall in the
Keychain; at first start with no stored server address the app deletes that
unreachable key.

## Known risk R1: device-login phishing

Paperclip's device login lets a client ask for a board key that a signed-in
user approves in the browser. In the Paperclip release we target (checked
against `v2026.1106.0`), the approval page does not show a code the user can
match to the device that started the request, and the client name is not
verified. An attacker can start their own request and trick a user into
approving it (for example by link, message or a lookalike "CLI" prompt), and
the attacker then receives a key with the user's full power.

This is a Paperclip server property that Paperplane cannot fix. We decided not
to report it upstream. What you can do:

- Approve a device-login request **only if you started it yourself, just now**,
  from Paperplane.
- Expect the approval page to talk about a "CLI" or "terminal"; that wording is
  Paperclip's.
- Prefer the in-app email-and-password sign-in where available. It does not use
  the approval page.
- Review and revoke keys regularly; key creation and revocation appear in the
  Paperclip audit log.

## Supported versions

Only the latest release of Paperplane receives security fixes.

## Handling secrets in this repository

Never commit real tokens. Test fixtures use fake values. CI scans for secrets
with `gitleaks`, and GitHub secret scanning and push protection are enabled.
