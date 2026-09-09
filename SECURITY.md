# Security Policy

## Supported version

Security fixes currently target the latest published release and the current `main` branch.

## Reporting a vulnerability

Use GitHub private vulnerability reporting from this repository's **Security** tab. Do not open a public Issue for an unpatched vulnerability.

Include only the minimum reproducible information. Never submit a real API Key, private EPUB, translated book, personal file path, account identifier, or credential-bearing log. Replace sensitive values with synthetic placeholders and confirm that screenshots are redacted.

## Secret exposure

If a real API Key is exposed anywhere, revoke it with the relevant provider immediately. Removing it from a later commit is not sufficient because Git history and caches may retain it.

## Product credential model

API Keys are held in memory for the current App session only and are cleared when the App exits. The App does not use macOS Keychain persistence.
