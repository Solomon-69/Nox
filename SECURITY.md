# Security policy

## Supported versions

Only the latest release of Nox gets fixes. Please update before reporting.

## Reporting a problem

Please do not open a public issue for security problems. Report them privately through
GitHub instead: open the repository's **Security** tab and choose **Report a vulnerability**
([direct link](https://github.com/Solomon-69/Nox/security/advisories/new)).

Include what you found, the steps to reproduce it, and the Nox version and system you used.
You should hear back within a week. Once a fix is released, you are welcome to be credited in
the release notes.

## What Nox can and cannot do

- It makes no network connections. There are no accounts, analytics, ads or update checks.
- The Safari extension is sandboxed. It asks the app one yes or no question (is "Websites
  follow your Mac" on?) and never sends a page address or page content to the app.
- The Chrome extension has no background script and does not talk to the app.
- On Mac it uses Automation (System Events) only to switch light and dark. Screen Recording is
  optional and only used for the smooth fade, with the picture kept in memory and never saved.
- The extensions run a script on every page because they must read the page's own colours.
  That script runs inside your browser and sends nothing anywhere.

If you find Nox doing anything outside this list, that is a bug worth reporting. Full detail is
in [PRIVACY.md](PRIVACY.md).

## Checking a download

Each release includes `SHA256SUMS.txt`. After downloading, you can check a file with:

```sh
shasum -a 256 -c SHA256SUMS.txt --ignore-missing
```

Mac releases are ad-hoc signed unless the release notes say they are signed with a Developer ID
and notarised by Apple. Building from source is always an option (see the README).
