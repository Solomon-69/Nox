# Privacy

Nox collects no data. Nothing you do in Nox, in Safari or in Chrome is sent anywhere.

This is what the code actually does:

## No network access

The Nox app, the Safari extension and the Chrome extension contain no network code. They
make no web requests, have no analytics, no crash reporting and no accounts.

## The web extensions

- The extensions run a small script on every page you visit. That is why they ask for
  access to all websites. The script reads the page's own colours to decide whether it is
  already dark, and if not, adds a dark style to the page. All of this happens inside your
  browser, on that page.
- The Safari extension asks the Nox app one question through Safari's built-in native
  messaging: "is 'Websites follow your Mac' switched on?" The app answers yes or no. No page
  address or page content is passed to the app.
- The Chrome extension has no background script and does not talk to the Nox app. It simply
  follows the light or dark setting that Chrome reports.

## What is stored on your Mac

- Your settings (for example the night schedule times and which switches are on) are kept in
  the standard macOS preferences for `com.solomon.DarkSwitch`.
- A short troubleshooting log about the smooth fade is written to
  `~/Library/Logs/DarkSwitch.log`. It contains times and technical notes only, never page
  content or personal information. You can delete it at any time.

## Permissions Nox asks for

- **Automation (System Events):** used only to switch macOS between light and dark mode.
- **No Screen Recording, ever:** the smooth fade is done by macOS itself (or, on a Mac where
  that isn't available, a soft veil Nox draws). Nox never looks at, captures or records your
  screen, and never asks for Screen Recording.
- **Mouse position and clicks:** Nox watches pointer movement to know when the pointer is over
  its menu bar icon, and watches clicks while its panel is open so it can close the panel when
  you click elsewhere. It does not record or store any of this.

## Questions

If you find anything in the code that does not match this page, please open an issue.
