# Third-party material in Nox

Nox is Copyright (c) 2026 Solomon, MIT licence (see LICENSE).

| Part | Licence | Where |
| --- | --- | --- |
| Microsoft Edge WebView2 SDK 1.0.3912.50 (Windows app only), (c) Microsoft | BSD-style, see the NuGet package | NuGet reference in `windows/*.csproj`; the WebView2 Runtime itself is part of Windows and is not shipped |
| .NET 8 / Windows Forms (Windows app only, installed separately) | MIT | https://github.com/dotnet/runtime |

No fonts, sounds or other open-source code are bundled. The Chrome extension `key` in `ChromeExtension/manifest.json` is a public key (it only fixes the extension's ID), not a secret.

## Trademarks

Apple, Safari, Mac and macOS are trademarks of Apple Inc.; Chrome is a trademark of Google LLC; Windows is a trademark of Microsoft Corporation. Not affiliated with or endorsed by them.
