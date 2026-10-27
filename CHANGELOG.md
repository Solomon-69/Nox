# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.1] - 2026-10-27

### Fixed
- Small grey text is darker and easier to read in light and dark.

## [1.3] - 2026-10-27

### Fixed
- Switching dark mode no longer leaves the menu bar icon alone in a box with bars either side: the veil now leaves the whole menu bar uncovered and macOS changes it with its own fade.

## [1.0.2] - 2026-10-27

### Fixed
- Nox never asks for Screen Recording any more: the smooth fade is now a soft veil Nox draws itself, and the Allow buttons are gone.
- Every click on the menu bar switch counts: a click during a switch is queued, and System Events is started early so the first click works.
- Dark mode stays on while Nox's dark is on: checked again when apps open, the Mac wakes, and Nox restarts.
- Settings, Share and Quit sit in three equal columns at the bottom of the panel, with Share centred.

### Added
- Welcome tip: Nox works best when most apps use Auto/System appearance.

## [1.0.1] - 2026-10-23

### Changed
- New welcome: three pages (what Nox does, the permissions, three tips), frosted glass panel on a plain soft backdrop, logo centred.
- First-launch animation like the iPhone unlock: logo and rows rise in with a staggered spring. Each page plays once and never replays; Reduce Motion gets a fade.
- Windows welcome gets the same glass panel and three tips on the last page.

## [Unreleased]

### Added
- Polished GitHub page: new README with light and dark screenshots, Safari setup steps,
  Windows install and FAQ.
- Issue forms, pull request template, `SECURITY.md`, `CONTRIBUTING.md` and a release checklist.
- Release workflow that builds the Mac app and the Windows app, with optional Developer ID
  signing and notarisation when the repository has the secrets.

## [1.0.0] - 2026-10-22

### Added
- Menu bar app that flips your Mac between light and dark mode with one click.
- Right-click (or Option-click) panel and a Settings window.
- Safari web extension that turns websites dark while your Mac is in dark mode, and
  leaves sites that are already dark alone.
- Unpacked Chrome extension with the same behaviour, loadable in Developer mode.
- "Dark at night" schedule (dark from 20:00 to 07:00 by default, adjustable).
- Optional smooth fade between light and dark (needs Screen Recording permission).
- Open at login.
- First-run welcome window that walks through each permission.
- `make-release.sh`, which builds the app and packs it into `release/Nox.dmg`.

[Unreleased]: https://github.com/Solomon-69/Nox/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Solomon-69/Nox/releases/tag/v1.0.0
