# Third-Party Notices

Stage 1 source references the following build, UI and test packages. No package binaries are committed to this repository; NuGet restores them on the Windows build machine.

| Component | Pinned version | Purpose | License |
| --- | ---: | --- | --- |
| Microsoft.WindowsAppSDK | 2.4.0 | WinUI 3 and Windows App SDK | Microsoft package license |
| Microsoft.Windows.SDK.BuildTools | 10.0.28000.2705 | Windows SDK build tools | Microsoft package license |
| Microsoft.Windows.SDK.BuildTools.WinApp | 0.6.1 | Packaged WinUI `dotnet run` support | MIT |
| Microsoft.NET.Test.Sdk | 18.10.0 | .NET test host integration | MIT |
| MSTest.TestAdapter | 4.4.0 | MSTest discovery and execution | MIT |
| MSTest.TestFramework | 4.4.0 | Unit-test framework | MIT |

The application calls Windows Credential Manager directly through the Windows `advapi32` API and does not add a third-party credential package.

Qwen and DeepSeek are external network services. No provider SDK, model, credential or service code is bundled in Stage 1, and Stage 1 makes zero provider requests.

The brand icon is copied from the project's existing Apache-2.0 public source repository. The included Stage 1 EPUB fixture and its contents are authored specifically for this project; see `fixtures/FIXTURE_PROVENANCE.md`.

Before binary distribution, restore output and transitive dependencies must be audited again and the shipped notices regenerated from the actual lock graph.
