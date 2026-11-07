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
