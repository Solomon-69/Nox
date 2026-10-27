// Logic checks for NoxDark (keep-dark rules). Run: tests/logic/run.sh
import Foundation

var failures = 0
func check(_ ok: Bool, _ name: String) { print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1 } }

// Pages darken only when Nox's dark is on.
check(NoxDark.next(false, after: .noxSwitching(toDark: true)), "switching to dark turns pages dark")
check(!NoxDark.next(true, after: .noxSwitching(toDark: false)), "switching to light clears pages")
check(NoxDark.next(false, after: .launched(intentDark: true, systemDark: true)), "relaunch keeps Nox dark")
check(!NoxDark.next(true, after: .launched(intentDark: false, systemDark: true)), "relaunch: dark from elsewhere stays stock")
check(!NoxDark.next(true, after: .launched(intentDark: true, systemDark: false)), "relaunch: Mac light, pages not dark")

// The wish to stay dark.
check(NoxDark.nextIntent(false, after: .noxSwitching(toDark: true)), "Nox switch to dark sets the wish")
check(!NoxDark.nextIntent(true, after: .noxSwitching(toDark: false)), "Nox switch to light clears the wish")
check(!NoxDark.nextIntent(true, after: .appearanceChanged(byNox: false, nowDark: false)), "light chosen elsewhere is respected")
check(NoxDark.nextIntent(true, after: .appearanceChanged(byNox: false, nowDark: true)), "dark from elsewhere keeps the wish")
check(NoxDark.nextIntent(true, after: .quitting), "the wish survives quitting")
check(NoxDark.nextIntent(true, after: .launched(intentDark: true, systemDark: false)), "the wish survives launch")

// When Nox puts dark back.
check(NoxDark.shouldReassertDark(intentDark: true, systemDark: false, switching: false), "Mac went light behind Nox: put dark back")
check(!NoxDark.shouldReassertDark(intentDark: true, systemDark: true, switching: false), "already dark: nothing to do")
check(!NoxDark.shouldReassertDark(intentDark: false, systemDark: false, switching: false), "Nox dark off: leave light alone")
check(!NoxDark.shouldReassertDark(intentDark: true, systemDark: false, switching: true), "mid-switch: wait")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
