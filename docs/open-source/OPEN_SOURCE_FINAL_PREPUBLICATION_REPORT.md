# Open-source final pre-publication report

Audit date: 2026-09-09

Candidate version: 1.0.1 (4)

This report records the local pre-publication state. It contains no credentials, private paths, user EPUB data, or copied private Git history.

## License and attribution

- The repository contains the complete Apache License 2.0 text in `LICENSE`.
- The `LICENSE` SHA-256 is `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`.
- Project attribution is recorded in `NOTICE` and is consistent with the App metadata.
- No bundled third-party source, package, font, model, SDK, or reference screenshot requires an additional redistribution license.
- The self-authored EPUB fixture includes readable source and provenance.

## Privacy and repository isolation

- Local static scans found zero exposed secrets and zero private-information matches.
- No real user EPUB, runtime data, log, checkpoint, database, release binary, symlink, or hardlink is included.
- No private repository history, Git object alternate, or private remote was copied.
- The source repository has one new local root commit only and remains unpublished.

## Verification

| Gate | Result |
| --- | --- |
| Unit tests | 71 executed, 0 failures, 1 optional external-fixture test skipped |
| UI acceptance tests | 7/7 passed, 0 failures |
| Fresh-clone security scan | Passed |
| Fresh-clone build | Passed |
| Generated build output included in source commit | No |

The optional unit-test skip requires a separately supplied external EPUB and is not needed for the self-contained public-source acceptance suite.

## Final gates

`LICENSE_SELECTED=Apache-2.0`

`LICENSE_COMPLIANCE=PASS`

`UI_TESTS=7/7 PASS`

`UNIT_TESTS=PASS`

`FRESH_BUILD=PASS`

`SECRET_EXPOSURE=0`

`PRIVATE_INFORMATION_EXPOSURE=0`

`PRIVATE_GIT_HISTORY_COPIED=NO`

`SOURCE_REPO_PUBLISHED=NO`

`READY_FOR_OPEN_SOURCE_PUBLICATION=YES`

Publication remains intentionally stopped pending the user's final confirmation.
