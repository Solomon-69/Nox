# Release checklist

Steps for publishing Nox as the public repository `Solomon-69/Nox`. Nothing here has been
pushed yet.

## 1. Start the public repository from a fresh history

The private history of this folder may contain personal details from earlier signing work.
Rewriting old commits is easy to get wrong, so the public repository should start from one
clean commit:

```sh
# from a clean checkout of the current main branch
git checkout --orphan public-main
git add -A
git commit -m "Nox 1.0"
# check before pushing: no emails, Apple IDs, Team IDs or personal paths
git grep -nIiE '@(gmail|icloud|me|outlook)\.com|apple ?id|/Users/' -- ':!RELEASE-CHECKLIST.md' || echo "clean"
git remote add public https://github.com/Solomon-69/Nox.git
git push public public-main:main
```

Keep the old history only in the private copy.

## 2. Before the first public push

- [ ] `git grep` check above prints `clean`
- [ ] `Local.xcconfig` is not tracked (it is in `.gitignore`)
- [ ] `project.yml` and `Signing.xcconfig` hold no Team ID or signing identity
- [ ] README badges and links point at `Solomon-69/Nox`
- [ ] Screenshots in `docs/img/` are current
- [ ] `release/*.dmg` and `build/` are not tracked

## 3. Repository settings on GitHub

- [ ] Description: "One click flips your Mac between light and dark. Websites follow along."
- [ ] Topics: `macos`, `menu-bar`, `menubar-app`, `dark-mode`, `safari-extension`, `chrome-extension`, `swift`, `windows`
- [ ] Social preview image: `docs/img/settings-dark.png` (or a 1280x640 crop of it)
- [ ] Private vulnerability reporting: on (Settings > Code security)
- [ ] Issues on, Discussions optional

## 4. Optional: signed and notarised Mac builds

Add these repository secrets (Settings > Secrets and variables > Actions). The release workflow
uses them when all are present and skips signing when they are not:

`MACOS_CERT_P12`, `MACOS_CERT_PASSWORD`, `MACOS_SIGN_IDENTITY`,
`NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_PASSWORD`.

Details are at the top of `.github/workflows/release.yml`. Never put these values in a file.
Without them, the Safari extension counts as unsigned and people need the extra Developer steps
described in the README.

## 5. Cutting a release

- [ ] Set `MARKETING_VERSION` (and bump `CURRENT_PROJECT_VERSION`) in `project.yml`
- [ ] Move the `[Unreleased]` notes in `CHANGELOG.md` under the new version heading
- [ ] Tag and push: `git tag v1.0.1 && git push public v1.0.1`
- [ ] Check the release has `Nox.dmg`, `Nox-mac.zip`, `Nox-windows.zip` and `SHA256SUMS.txt`
- [ ] On a second Mac: install from the dmg, open it, flip dark and light, follow the Safari steps and check a bright page goes dark
- [ ] On a Windows PC: unzip, run `Nox.exe`, flip the theme from the tray icon
