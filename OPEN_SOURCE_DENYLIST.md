# Open-source export denylist

The following content must never enter this repository:

- any previous `.git` directory, Git object, alternate object database, remote, tag, or private development history
- API keys, tokens, authorization headers, passwords, credential exports, private keys, certificates, provisioning profiles, or authentication state
- `.env` files or local configuration containing real values
- real user EPUB files, translated books, copyrighted book excerpts, user libraries, or personal test data
- real checkpoints, job databases, SQLite files, logs, crash reports, coverage output, or diagnostic captures
- build output, `DerivedData`, `.build`, caches, virtual environments, release bundles, DMG, ZIP, or App packages
- internal acceptance, security, Codex, migration, archive, recovery, or task-execution reports
- local absolute paths, computer names, private email addresses, phone numbers, addresses, network identifiers, or machine identifiers
- mature-reference source that is not part of the current product
- Ollama, local-LLM, review queues, semantic blocking gates, A/B/C review systems, or other features absent from the current product
- third-party reference screenshots, unlicensed images, fonts, icons, or other assets
- symlinks, hardlinks, path dependencies, or runtime/build dependencies on any non-public local repository

Unknown or unverified fixtures, assets, documents, and dependencies are excluded by default.
