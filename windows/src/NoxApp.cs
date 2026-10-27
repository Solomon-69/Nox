using System.Diagnostics;
using System.Text.Json;
using Kit;

namespace Nox;

internal sealed class Settings
{
    public bool NightSchedule { get; set; }
    public int DarkAt { get; set; } = 20 * 60 + 30;
    public int LightAt { get; set; } = 7 * 60 + 30;
    public bool SmoothFade { get; set; } = true;
    public bool IntroDone { get; set; }

    public Settings Clean()
    {
        DarkAt = ((DarkAt % 1440) + 1440) % 1440;
        LightAt = ((LightAt % 1440) + 1440) % 1440;
        return this;
    }
}

/// <summary>
/// Nox for Windows: one click flips the whole PC between light and dark. "Dark at night" switches by itself
/// at two set times, "Smooth fade" cross-fades the screen while it happens. Websites follow with the
/// Chrome/Edge extension (loaded by hand, see the panel).
/// </summary>
internal sealed class NoxApp : ApplicationContext
{
    public const string Version = "1.0.0";
    private const int ScheduleTickMs = 20_000;
    private const int KnobSlideMs = 380;   // the panel's switch spring (.34s) before the screen picture is taken
    private static readonly Color LightBack = Color.FromArgb(0xF3, 0xF0, 0xFE);
    private static readonly Color DarkBack = Color.FromArgb(0x0C, 0x10, 0x22);

    private readonly LaunchArgs args;
    private readonly Settings s;
    private readonly Control invoker = new();
    private readonly SystemTheme theme;
    private readonly TrayPanel panel;
    private readonly Tray tray;
    private readonly ToolStripMenuItem darkItem;
    private readonly System.Windows.Forms.Timer schedule = new() { Interval = ScheduleTickMs };
    private bool? lastNight;
    private bool switching;
    private bool exiting;
    private string? error;
    private (bool Apps, bool Taskbar)? testBefore;

    public NoxApp(LaunchArgs args)
    {
        this.args = args;
        _ = invoker.Handle;
        s = Files.Load<Settings>("settings.json").Clean();
        Files.RefreshLoginPath();

        theme = new SystemTheme(invoker);
        panel = new TrayPanel("Nox", 380, 520, BootScript, () => theme.AppsDark, LightBack, DarkBack);
        panel.Message += OnMessage;
        panel.Ready += OnReady;
        panel.Shown2 += () => { Push(); _ = RepollExtension(); };
        theme.Changed += () => { panel.ApplyColors(); UpdateTray(); Push(); };

        darkItem = new ToolStripMenuItem("Dark mode", null, (_, _) => Flip(!theme.AppsDark));
        var openItem = new ToolStripMenuItem("Open Nox", null, (_, _) => panel.ShowPanel(tray!.Center()));
        openItem.Font = new Font(openItem.Font, FontStyle.Bold);
        var quitItem = new ToolStripMenuItem("Quit", null, (_, _) => Quit());
        tray = new Tray("Nox", new ToolStripItem[] { darkItem, openItem, new ToolStripSeparator(), quitItem }, () => theme.TaskbarDark);
        tray.Opening += () => darkItem.Checked = theme.AppsDark;
        tray.LeftClick += at => panel.Toggle(at);
        UpdateTray();
        tray.Visible = true;

        schedule.Tick += (_, _) => CheckSchedule(false);
        schedule.Start();
        CheckSchedule(true);
        Application.Idle += StartOnce;
    }

    private void StartOnce(object? sender, EventArgs e)
    {
        Application.Idle -= StartOnce;
        _ = panel.InitializeAsync();
    }

    // ---------- Switching ----------

    private async void Flip(bool dark)
    {
        if (switching || exiting) return;
        if (dark == theme.AppsDark && dark == theme.TaskbarDark) { Push(); return; }
        switching = true;
        error = null;
        var wasOpen = panel.Visible;
        // The panel stays open through the whole switch (fade included), even while Windows shuffles focus.
        panel.Hold(s.SmoothFade ? 3500 : 1200);
        try
        {
            void Apply()
            {
                error = WinTheme.Set(dark);
                theme.Refresh();
            }
            if (s.SmoothFade)
            {
                // Let the panel's own switch finish sliding first, so the picture shows it already in place.
                if (wasOpen) await Task.Delay(KnobSlideMs);
                await ScreenFade.RunAsync(Apply, wasOpen ? panel.Handle : IntPtr.Zero);
            }
            else Apply();
        }
        finally
        {
            switching = false;
            panel.Hold(400);
            if (wasOpen && !panel.Visible && !exiting)
            {
                Files.Log("Panel was closed by the switch: reopening it");
                panel.ShowPanel();
            }
            UpdateTray();
            Push();
        }
    }

    /// <summary>Switches only when the clock crosses a set time, so flipping by hand in between sticks (as on the Mac).</summary>
    private void CheckSchedule(bool force)
    {
        if (!s.NightSchedule) { lastNight = null; return; }
        var now = DateTime.Now;
        var night = WinTheme.IsNight(now.Hour * 60 + now.Minute, s.DarkAt, s.LightAt);
        var crossed = force || (lastNight != null && lastNight != night);
        lastNight = night;
        if (!crossed || night == theme.AppsDark || switching) return;
        Flip(night);
        if (!force) tray.Balloon("Nox", night ? "Dark mode on for the night." : "Good morning: light mode is back on.");
    }

    // ---------- Tray ----------

    private void UpdateTray()
    {
        var fg = theme.TaskbarDark ? Color.White : Color.FromArgb(0x1A, 0x1A, 0x1A);
        var dark = theme.AppsDark;
        tray.SetGlyph((g, px) => Glyph.Draw(g, px, dark, fg));
        tray.Text = dark ? "Nox: dark" : "Nox: light";
    }

    // ---------- Page bridge ----------

    private string BootScript() => $"window.__BOOT__ = {StateJson()};";

    private void Push()
    {
        if (panel.IsReady) panel.Run($"window.app && app.update({StateJson()})");
    }

    private string StateJson() => JsonSerializer.Serialize(new
    {
        dark = theme.AppsDark,
        schedule = s.NightSchedule,
        darkAt = s.DarkAt,
        lightAt = s.LightAt,
        fade = s.SmoothFade,
        login = Files.LoginEnabled(),
        error,
        ext = new { chrome = Extension.Installed("chrome"), edge = Extension.Installed("edge") },
        version = Version,
        intro = ShowIntro,
    });

    /// The welcome shows on the first run only. Automated test runs skip it unless they ask for it.
    private bool ShowIntro => !s.IntroDone && (args.SelfTestPath == null || args.Has("--test-intro"));

    private static bool Bool(JsonElement m, string name) => m.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.True;

    private static int Int(JsonElement m, string name, int fallback) =>
        m.TryGetProperty(name, out var v) && v.TryGetInt32(out var i) ? i : fallback;

    private void OnMessage(string type, JsonElement m)
    {
        switch (type)
        {
            case "flip": Flip(Bool(m, "dark")); return;
            case "schedule":
                s.NightSchedule = Bool(m, "on");
                Save();
                CheckSchedule(true);
                break;
            case "times":
                s.DarkAt = Int(m, "darkAt", s.DarkAt);
                s.LightAt = Int(m, "lightAt", s.LightAt);
                s.Clean();
                Save();
                CheckSchedule(true);
                break;
            case "fade": s.SmoothFade = Bool(m, "on"); Save(); break;
            case "login": Files.SetLogin(Bool(m, "on")); break;
            case "extFolder": Extension.OpenFolder(); return;
            case "extPage":
                Extension.Setup(m.TryGetProperty("browser", out var b) ? b.GetString() : "chrome");
                _ = RepollExtension();
                return;
            case "close": panel.HidePanel(); return;
            case "introDone": s.IntroDone = true; Save(); panel.StayOpen = args.TestOpen; return;
            case "quit": Quit(); return;
            default: return;
        }
        Push();
    }

    /// <summary>While the panel is open, notice the moment the extension gets added in the browser.</summary>
    private async Task RepollExtension()
    {
        for (var i = 0; i < 90 && panel.Visible && !exiting; i++)
        {
            await Task.Delay(2000);
            Push();
        }
    }

    private void Save() => Files.Save("settings.json", s);

    // ---------- Test hooks and outside signals ----------

    private async void OnReady()
    {
        Push();
        if (ShowIntro && !args.TestOpen)
        {
            // First run: open the panel on its own so the welcome is seen, and keep it open until it is done.
            panel.StayOpen = true;
            panel.ShowPanel(tray.Center());
        }
        if (args.TestOpen)
        {
            panel.StayOpen = true;
            panel.ShowPanel(tray.Center());
        }
        if (args.Has("--test-show"))
        {
            // Like a real click on the tray icon: opens the panel, which closes again when focus leaves it.
            panel.ShowPanel(tray.Center());
            await Task.Delay(1200);
            if (args.SelfTestPath != null)
            {
                var rect = await panel.Eval("(()=>{const r=document.getElementById('big').getBoundingClientRect();return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2,dpr:devicePixelRatio})})()");
                var pb = panel.Bounds;
                Files.WriteJson(args.SelfTestPath + ".rect", new { rect = JsonSerializer.Deserialize<string>(rect), panel = new[] { pb.X, pb.Y, pb.Width, pb.Height }, visible = panel.Visible });
            }
        }
        if (args.Has("--test-how")) panel.Run("document.getElementById('howBtn').click()");
        if (args.Has("--test-flip"))
        {
            await Task.Delay(800);
            testBefore = SystemTheme.Read();
            if (args.SelfTestPath != null) Files.WriteJson(args.SelfTestPath + ".flip", new { at = DateTime.Now });
            Flip(!theme.AppsDark);
            await Task.Delay(2200);
        }
        if (args.Has("--test-zoomprobe") && args.SelfTestPath != null) { await panel.ZoomProbe(args.SelfTestPath); return; }
        if (args.SelfTestPath != null)
        {
            await Task.Delay(1500);
            var b = panel.Bounds;
            var now = SystemTheme.Read();
            Files.WriteJson(args.SelfTestPath, new
            {
                app = "Nox",
                pid = Environment.ProcessId,
                ready = panel.IsReady,
                panelVisible = panel.Visible,
                panelBounds = new[] { b.X, b.Y, b.Width, b.Height },
                tray = tray.Bounds() is { } r ? new[] { r.X, r.Y, r.Width, r.Height } : null,
                appsDarkBefore = testBefore?.Apps,
                taskbarDarkBefore = testBefore?.Taskbar,
                appsDarkAfter = now.apps,
                taskbarDarkAfter = now.taskbar,
                fadeUsed = s.SmoothFade,
                error,
                extensionFiles = Resources.Under("ext/").Count(),
                extensionId = Extension.Id,
            });
            static Color Fg(bool darkBar) => darkBar ? Color.White : Color.FromArgb(0x1A, 0x1A, 0x1A);
            Tray.SaveSheet(Path.ChangeExtension(args.SelfTestPath, ".icons.png"), new Action<Graphics, float, bool>[]
            {
                (g, px, darkBar) => Glyph.Draw(g, px, false, Fg(darkBar)),
                (g, px, darkBar) => Glyph.Draw(g, px, true, Fg(darkBar)),
            });
        }
    }

    public void OpenFromOutside() => Post(() => panel.ShowPanel(tray.Center()));

    public void QuitFromOutside() => Post(Quit);

    private void Post(Action a)
    {
        try { if (!exiting) invoker.BeginInvoke(a); }
        catch (Exception ex) when (ex is ObjectDisposedException or InvalidOperationException) { }
    }

    private async void Quit()
    {
        if (exiting) return;
        exiting = true;
        schedule.Stop();
        await panel.FadeOutAsync();
        tray.Dispose();
        theme.Dispose();
        panel.Dispose();
        schedule.Dispose();
        ExitThread();
    }
}

/// <summary>"Websites follow your PC": the Chrome/Edge extension (ChromeExtension folder, carried inside Nox.exe).</summary>
internal static class Extension
{
    public static string Folder => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Nox", "ChromeExtension");

    /// <summary>Writes a fresh copy of the extension and shows it in File Explorer, ready for "Load unpacked".</summary>
    public static void OpenFolder()
    {
        WriteFolder();
        try { Process.Start(new ProcessStartInfo("explorer.exe", $"\"{Folder}\"") { UseShellExecute = true }); }
        catch (Exception ex) { Files.Log($"Extension folder failed: {ex.Message}"); }
    }

    private static void WriteFolder()
    {
        try
        {
            Directory.CreateDirectory(Folder);
            foreach (var name in Resources.Under("ext/"))
            {
                var target = Path.Combine(Folder, name["ext/".Length..].Replace('/', Path.DirectorySeparatorChar));
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                using var src = Resources.Open(name)!;
                using var dst = File.Create(target);
                src.CopyTo(dst);
            }
        }
        catch (Exception ex)
        {
            Files.Log($"Extension folder failed: {ex.Message}");
        }
    }

    /// The extension's fixed ID (from the key in its manifest), the same on every PC.
    public static string Id
    {
        get
        {
            try
            {
                using var doc = JsonDocument.Parse(Resources.Open("ext/manifest.json")!);
                var der = Convert.FromBase64String(doc.RootElement.GetProperty("key").GetString()!);
                var hash = System.Security.Cryptography.SHA256.HashData(der);
                return new string(hash.Take(16).SelectMany(b => new[] { (char)('a' + (b >> 4)), (char)('a' + (b & 15)) }).ToArray());
            }
            catch (Exception) { return ""; }
        }
    }

    /// <summary>Is the extension added and on in any profile of this browser? Read from the browser's own settings files.</summary>
    public static bool Installed(string browser)
    {
        try
        {
            var id = Id;
            if (id.Length == 0) return false;
            var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                                    browser == "edge" ? @"Microsoft\Edge\User Data" : @"Google\Chrome\User Data");
            if (!Directory.Exists(root)) return false;
            foreach (var profile in Directory.EnumerateDirectories(root))
                foreach (var name in new[] { "Secure Preferences", "Preferences" })
                {
                    var file = Path.Combine(profile, name);
                    if (!File.Exists(file)) continue;
                    using var fs = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                    using var doc = JsonDocument.Parse(fs);
                    if (doc.RootElement.TryGetProperty("extensions", out var e) && e.TryGetProperty("settings", out var st)
                        && st.TryGetProperty(id, out var x))
                        return !x.TryGetProperty("disable_reasons", out var dr) || dr.ValueKind != JsonValueKind.Number || dr.GetInt32() == 0;
                }
        }
        catch (Exception) { }
        return false;
    }

    /// <summary>One click: fresh extension copy, its folder path on the clipboard, the browser's extensions page open.</summary>
    public static void Setup(string? browser)
    {
        WriteFolder();
        try { Clipboard.SetText(Folder); } catch (Exception) { }
        OpenExtensionsPage(browser);
    }

    /// <summary>Opens chrome://extensions or edge://extensions. Browsers only accept these from their own command line.</summary>
    public static void OpenExtensionsPage(string? browser)
    {
        var edge = browser == "edge";
        var url = edge ? "edge://extensions" : "chrome://extensions";
        try
        {
            Process.Start(new ProcessStartInfo(edge ? "msedge.exe" : "chrome.exe", url) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            Files.Log($"Could not open {url}: {ex.Message}");
            try { Clipboard.SetText(url); } catch (Exception) { }
            MessageBox.Show($"{(edge ? "Edge" : "Chrome")} did not open. The address {url} is copied: paste it into the address bar.",
                            "Nox", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
    }
}
