# Open-source privacy audit

Audit date: 2026-09-09

Candidate version: 1.0.1 (4)

Scope: every file eligible for the initial public-source candidate, excluding the new repository's own empty Git metadata and generated build output.

## Rules

The audit checked for:

- credential-like assignments and common API, cloud, private-key, authorization, and token formats
- personal home paths, repository paths, private email addresses, machine identifiers, network identifiers, and other personal data
- real user EPUB files, known user book titles, copyrighted excerpts, logs, checkpoints, databases, crash/coverage output, and release binaries
- symlinks, hardlinks, Git object alternates, copied history, private remotes, and local path dependencies
- unapproved third-party images, screenshots, fonts, packages, and source code

Sensitive matches are never reproduced in this report.

## Results

| Gate | Result |
| --- | --- |
| Real secret exposure | 0 |
| Personal information exposure | 0 |
| Private email exposure | 0 |
| Personal absolute path exposure | 0 |
| Private/reference repository path exposure | 0 |
| Real user EPUB exposure | 0 |
| Copyright-sensitive user book content | 0 |
| Logs, checkpoints, and databases | 0 |
| Release binaries | 0 |
| Symlinks and hardlinks | 0 |
| Private Git history and object alternates | 0 |
| Third-party reference images | 0 |

The public GitHub handle used by the existing support repository appears only where it identifies public URLs or the existing public bundle identifier. No private email or real name is included.

The repository-provided scanner and additional static expressions ran locally. Optional `gitleaks` and `trufflehog` executables were not installed, so no source was uploaded and no network scanner was used.

## Credential behavior verified from source

API Keys are held in a session-only in-memory credential store. They are cleared when the App exits and are not written to macOS Keychain, preferences, checkpoints, logs, or diagnostics.

## Conclusion

`PRIVACY_SCAN=PASS`

`SECRET_SCAN=PASS`

`SECRET_SCAN_LOCAL_ONLY=YES`

`PRIVATE_INFORMATION_EXPOSURE=0`

`PRIVATE_ABSOLUTE_PATH_EXPOSURE=0`

`PRIVATE_GIT_HISTORY_COPIED=NO`
