# Automated Windows test for Nox: start it, flip Windows to dark (with the smooth fade), check the registry
# and the panel, check "Dark at night" switches by itself, then quit. Screenshots go to $Shots.
param([string]$Exe = 'out/Nox/Nox.exe', [string]$Shots = 'shots')
. "$PSScriptRoot/winlib.ps1"
New-Item -ItemType Directory -Force $Shots | Out-Null
$Exe = (Resolve-Path $Exe).Path
$Shots = (Resolve-Path $Shots).Path
$settings = Join-Path $env:APPDATA 'Nox\settings.json'

# ---- Run 1: light to dark with the smooth fade ----
Set-Theme $false
$before = Theme-Values
Write-Host "Before: AppsUseLightTheme=$($before.Apps) SystemUsesLightTheme=$($before.System)"
$json = Join-Path $Shots 'nox-selftest.json'
$p = Start-App $Exe @('--test-open', '--test-flip', "--selftest=$json")
Check (Promote-TrayIcon 'Nox.exe') 'tray icon registered with Windows (NotifyIconSettings entry)'
if (Wait-File "$json.flip" 120) {
  # Frames through the fade (each screenshot itself takes a moment; the app log has the exact times).
  $t0 = Get-Date
  foreach ($i in 1..24) {
    $ms = [int]((Get-Date) - $t0).TotalMilliseconds
    Save-Screen (Join-Path $Shots ("02-nox-fade-{0:d2}-{1}ms.png" -f $i, $ms))
    Start-Sleep -Milliseconds 30
  }
} else { Fail 'flip never started' }
Check (Wait-File $json 60) 'self-test file written'
$r = Get-Content $json -Raw | ConvertFrom-Json
Write-Host ($r | ConvertTo-Json -Depth 5)
Check (-not $p.HasExited) 'process alive'
Check $r.ready 'WebView2 page loaded'
Check $r.panelVisible 'panel opened (--test-open)'
Check ($null -ne $r.tray) 'tray icon has a position on screen'
Check ($r.extensionId -match '^[a-p]{32}$') "extension ID worked out ($($r.extensionId))"
Check ($r.extensionFiles -ge 3) 'Chrome/Edge extension files carried inside Nox.exe'
$after = Theme-Values
Write-Host "After: AppsUseLightTheme=$($after.Apps) SystemUsesLightTheme=$($after.System)"
Check (($after.Apps -eq 0) -and ($after.System -eq 0)) 'registry flipped to dark (apps and taskbar)'
Check ($r.appsDarkBefore -eq $false -and $r.appsDarkAfter -eq $true) 'Nox saw the change itself'
Save-Screen (Join-Path $Shots '03-nox-desktop-dark.png')
$b = $r.panelBounds
Save-Crop (Join-Path $Shots '04-nox-panel-dark.png') $b[0] $b[1] $b[2] $b[3]
Save-TrayCorner (Join-Path $Shots '05-nox-tray-dark.png')
Check (Quit-App $Exe 'Nox') 'quit with --quit (clean exit)'

# ---- Run 2: light panel with the extension how-to open ----
Set-Theme $false
$json2 = Join-Path $Shots 'nox-selftest-how.json'
$p2 = Start-App $Exe @('--test-open', '--test-how', "--selftest=$json2")
[void](Promote-TrayIcon 'Nox.exe' 10)
Check (Wait-File $json2 120) 'second run: self-test file written'
$r2 = Get-Content $json2 -Raw | ConvertFrom-Json
Start-Sleep -Seconds 1
$b = $r2.panelBounds
Save-Crop (Join-Path $Shots '06-nox-panel-light-howto.png') $b[0] $b[1] $b[2] $b[3]
Save-TrayCorner (Join-Path $Shots '07-nox-tray-light.png')
Check (Quit-App $Exe 'Nox') 'second run: clean quit'

# ---- Run 3: "Dark at night" switches by itself when it is night ----
Set-Theme $false
$now = (Get-Date).Hour * 60 + (Get-Date).Minute
$darkAt = ($now + 1440 - 60) % 1440; $lightAt = ($now + 60) % 1440
New-Item -ItemType Directory -Force (Split-Path $settings) | Out-Null
@{ NightSchedule = $true; DarkAt = $darkAt; LightAt = $lightAt; SmoothFade = $false; IntroDone = $true } | ConvertTo-Json | Set-Content $settings
$p3 = Start-App $Exe @()
Start-Sleep -Seconds 6
$s3 = Theme-Values
Check (($s3.Apps -eq 0) -and ($s3.System -eq 0)) 'Dark at night switched to dark by itself at start (night time)'
Check (Quit-App $Exe 'Nox') 'third run: clean quit'
Remove-Item $settings -ErrorAction SilentlyContinue

# ---- Run 4: the first-run welcome shows in the panel ----
Set-Theme $false
$json4 = Join-Path $Shots 'nox-selftest-intro.json'
$p4 = Start-App $Exe @('--test-open', '--test-intro', "--selftest=$json4")
[void](Promote-TrayIcon 'Nox.exe' 10)
Check (Wait-File $json4 120) 'fourth run: self-test file written'
Start-Sleep -Seconds 2
$r4 = Get-Content $json4 -Raw | ConvertFrom-Json
$b = $r4.panelBounds
Save-Crop (Join-Path $Shots '08-nox-welcome-light.png') $b[0] $b[1] $b[2] $b[3]
Check (Quit-App $Exe 'Nox') 'fourth run: clean quit'
Remove-Item $settings -ErrorAction SilentlyContinue

# ---- Run 5: the real thing. Panel opened like a tray click (closes if it loses focus), PC dark, Smooth fade on.
# A real mouse click on the big switch must keep the panel open, slide the switch and fade the screen to light. ----
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Mouse {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  public static void Click() { mouse_event(2, 0, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(60); mouse_event(4, 0, 0, 0, UIntPtr.Zero); }
}
"@
Remove-Item $settings -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force (Split-Path $settings) | Out-Null
@{ NightSchedule = $false; SmoothFade = $true; IntroDone = $true } | ConvertTo-Json | Set-Content $settings
Set-Theme $true
$json5 = Join-Path $Shots 'nox-selftest-click.json'
$p5 = Start-App $Exe @('--test-show', "--selftest=$json5")
[void](Promote-TrayIcon 'Nox.exe' 10)
Check (Wait-File "$json5.rect" 120) 'fifth run: panel open, switch position known'
$r5 = Get-Content "$json5.rect" -Raw | ConvertFrom-Json
$sw = $r5.rect | ConvertFrom-Json
$cx = [int]($r5.panel[0] + $sw.x * $sw.dpr); $cy = [int]($r5.panel[1] + $sw.y * $sw.dpr)
Write-Host "switch at $cx,$cy (dpr $($sw.dpr))"
Check ([bool]$r5.visible) 'panel is open before the click'
Check (Window-Visible 'Nox') 'panel window is on screen before the click'
Save-Crop (Join-Path $Shots '09-click-0-before.png') $r5.panel[0] $r5.panel[1] $r5.panel[2] $r5.panel[3]
[void][Mouse]::SetCursorPos($cx, $cy)
Start-Sleep -Milliseconds 300
[Mouse]::Click()
$t0 = Get-Date; $everHidden = $false
foreach ($i in 1..14) {
  $ms = [int]((Get-Date) - $t0).TotalMilliseconds
  if (-not (Window-Visible 'Nox')) { $everHidden = $true }
  Save-Crop (Join-Path $Shots ("09-click-{0:d2}-{1}ms.png" -f $i, $ms)) $r5.panel[0] $r5.panel[1] $r5.panel[2] $r5.panel[3] 140
  Start-Sleep -Milliseconds 80
}
Start-Sleep -Seconds 2
Check (-not $everHidden) 'panel stayed open the whole time after the click'
Check (Window-Visible 'Nox') 'panel still open after the fade'
$a5 = Theme-Values
Check (($a5.Apps -eq 1) -and ($a5.System -eq 1)) 'the click switched Windows from dark to light'
Save-Screen (Join-Path $Shots '09-click-99-after.png')
Check (Quit-App $Exe 'Nox') 'fifth run: clean quit'
Remove-Item $settings -ErrorAction SilentlyContinue
Set-Theme $false

# ---- No zooming: Ctrl+wheel (= trackpad pinch), Ctrl and plus/minus/0 must do nothing ----
. "$PSScriptRoot/zoomtest.ps1"
Test-NoZoom $Exe 'Nox' $Shots
Set-Theme $false
Finish
