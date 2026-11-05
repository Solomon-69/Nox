# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [1.5.4] - 2026-11-05
### Fixed
- Updates: the bar follows the real download, then shows checking and installing, and a failed update says why.

## [1.5.3] - 2026-11-03
### Fixed
- The light/dark switch fades the way it did on Monday again: macOS's own smooth cross-fade of the whole screen when the Mac allows it, and the soft veil only when it does not.

## [1.5.2] - 2026-11-03
### Fixed
- The little arrow on top of the menu bar panel is one connected shape with the panel again. Only the panel's content springs in now; the colour behind it stays put, so there is no seam or gap where the arrow meets the body.
### Added
- `tests/popover-seam-check.py` takes a picture of the open panel in light and dark and fails if the arrow and body differ.

## [1.5.1] - 2026-11-03
### Fixed
- The light/dark fade is gentle again: a light veil that eases in and out, not a near-black cover over the whole screen.

## [1.5.0] - 2026-11-03
### Added
- Check for updates: a new row at the bottom of Settings looks for a newer Nox, checks the download against its checksum, and installs it with one click.
- Keyboard control in Settings: Up and Down move a highlight through the settings (wrapping around), Left and Right or Space and Return change the highlighted one, Esc clears the highlight and then closes the window.
### Changed
- The menu bar panel footer (Settings, Share, Quit) is smaller and centred, with a clearer hover.

## [1.4.3] - 2026-11-02
### Fixed
- Switching dark mode could crash Nox on some Macs. The cause was the old screen cross-fade, which called a private macOS function that behaves differently between macOS versions. That code is removed. Nox now uses only its own soft veil, the same on every Mac.

## [1.4.2] - 2026-11-02
### Fixed
- The light/dark fade is smooth again on macOS 27.2. The window server's held-screen cross-fade stopped working there (the screen repainted live and then cut). Nox now always uses its own soft veil: it eases in, hides the repaint, and eases away over 0.7 s.

## [1.4.1] - 2026-10-27

### Changed
- Nox never uses or asks for Screen Recording. The Screen Recording line and button are gone from Settings.
- Smoother fade: macOS itself now holds the whole screen, menu bar included, while the Mac switches, then cross-fades calmly into the new look. Nox never sees the screen.
- On a Mac where that isn't available, the soft veil is smoother too: the old look's colour over the whole screen, no box around the menu bar switch, easing away over half a second.

## [1.4] - 2026-10-27

### Changed
- The light/dark fade is back to the prettier picture version: when Nox is allowed in Screen Recording, a still picture of the whole screen, menu bar included, fades smoothly into the new look.
- Without Screen Recording, Nox uses the plain soft fade as before. Nox never asks for Screen Recording by itself; Settings shows one line with a button to open the right page if you want the smoothest fade.

## [1.3.3] - 2026-10-27

### Fixed
- No more dark box around the menu bar switch while the screen fades between light and dark: the whole screen, menu bar included, now fades as one.

## [1.3.2] - 2026-10-27

### Changed
- The fade when switching light and dark is back to the earlier, prettier version (the menu bar icon stays live while the rest of the screen fades).

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
