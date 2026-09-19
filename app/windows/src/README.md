# Source layout

- `EPUBTranslator.Core` — platform-independent product models, stable IDs, errors and service contracts. No WinUI or Windows API reference.
- `EPUBTranslator.Platform.Windows` — Credential Manager, Windows App SDK pickers, AppData, safe file copy and default-browser adapters.
- `EPUBTranslator.App` — WinUI 3 composition root and the three approved pages.

Stage 1 intentionally excludes the full EPUB parsing/reconstruction and provider transport implementations.
