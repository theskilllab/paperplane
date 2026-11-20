# lib/auth

Sign-in, board-key storage (secure storage only), key rotation and session
state. A key the app created is replaced after seven days: mint with the old
key, store the new record in one secure write, then revoke the old key. Never
log tokens or private URLs. Changes need code-owner review (see
`.github/CODEOWNERS`).
