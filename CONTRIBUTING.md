# Contributing to Nox

Thanks for your interest. Bug reports, ideas and pull requests are all welcome.

## Reporting bugs and ideas

Open an issue using the bug or idea form. For bugs, say whether you use Mac or Windows and the
version, which browser, and what happened. Security problems go through
[SECURITY.md](SECURITY.md) instead.

## Trying your changes

- Mac: build with XcodeGen and Xcode (see "Build from source" in the README).
- Chrome extension: load the `ChromeExtension` folder unpacked and reload it after each change.
- Windows: build with the .NET 8 SDK (`dotnet publish windows/Nox.csproj -c Release -r win-x64`).

## Pull requests

- Keep them small and focused. Describe what changed and how you tested it.
- Match the style of the code around you.
- Nox stays small: no network code, no analytics, no third-party dependencies on Mac.
- Never commit signing details. `Local.xcconfig` is git-ignored on purpose.

By contributing you agree that your contribution is released under the MIT licence.
