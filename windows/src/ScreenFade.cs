using System.Diagnostics;
using System.Drawing.Imaging;
using Kit;

namespace Nox;

/// <summary>
/// Smooth fade: a picture of every screen is laid over the desktop (click-through, never focused),
/// Windows switches underneath, then the picture fades away. Honest limits: apps that repaint slowly
/// can still finish changing after the fade, and protected video shows black in the picture.
/// </summary>
internal static class ScreenFade
{
    private const int MinHoldMs = 450, MaxHoldMs = 1600, QuietMs = 300;   // picture stays up until the live screen has stopped changing
    private const int FadeMs = 600;

    public static bool Running { get; private set; }

    /// <param name="keepAbove">A window (the Nox panel) that must stay live on top of the picture, so its own switch keeps sliding.</param>
    public static async Task RunAsync(Action flip, IntPtr keepAbove = default)
    {
        if (Running) { flip(); return; }
        Running = true;
        var overlays = new List<Overlay>();
        try
        {
            foreach (var screen in Screen.AllScreens)
            {
                var b = screen.Bounds;
                var shot = new Bitmap(b.Width, b.Height, PixelFormat.Format32bppPArgb);
                using (var g = Graphics.FromImage(shot)) g.CopyFromScreen(b.Location, Point.Empty, b.Size);
                var o = new Overlay(shot, b);
                o.ShowQuietly(keepAbove);
                overlays.Add(o);
            }
        }
        catch (Exception ex)
        {
            Files.Log($"Fade picture failed, switching without it: {ex.Message}");
        }
        var log = Stopwatch.StartNew();
        Files.Log($"Fade: {overlays.Count} picture(s) up: {string.Join(", ", overlays.Select(o => $"{o.Bounds} visible={o.Visible} opacity={o.Opacity:0.00}"))}");
        try
        {
            await Task.Delay(40);   // the picture is on screen before anything changes
            flip();
            if (overlays.Count == 0) return;
            Files.Log($"Fade: switched at {log.ElapsedMilliseconds} ms");
            await WaitUntilStable(overlays, log);
            Files.Log($"Fade: fading from {log.ElapsedMilliseconds} ms");
            var clock = Stopwatch.StartNew();
            while (clock.ElapsedMilliseconds < FadeMs)
            {
                var t = clock.ElapsedMilliseconds / (double)FadeMs;
                var eased = 1 - Math.Pow(1 - t, 3);   // ease out: moves at once, settles softly
                foreach (var o in overlays) o.Opacity = Math.Max(0.0, 0.999 * (1 - eased));
                await Task.Delay(15);
            }
        }
        finally
        {
            Files.Log($"Fade: done at {log.ElapsedMilliseconds} ms");
            foreach (var o in overlays) { o.Close(); o.Dispose(); }
            Running = false;
        }
    }

    /// Looks at the live screen (a plain copy leaves out see-through windows, so our picture is not in it)
    /// until it stops changing, so no app is still half-way when the fade starts.
    private static async Task WaitUntilStable(List<Overlay> overlays, Stopwatch log)
    {
        var sw = Stopwatch.StartNew();
        byte[]? prev = null; long quietSince = -1;
        while (sw.ElapsedMilliseconds < MaxHoldMs)
        {
            byte[]? now = null;
            try { now = Grid(overlays[0].Bounds); } catch { }
            if (now != null)
            {
                if (prev != null)
                {
                    var moving = 0;
                    for (var i = 0; i < now.Length; i++) if (Math.Abs(now[i] - prev[i]) > 4) moving++;
                    if (moving <= 1) { if (quietSince < 0) quietSince = sw.ElapsedMilliseconds; } else quietSince = -1;
                }
                prev = now;
                if (quietSince >= 0 && sw.ElapsedMilliseconds - quietSince >= QuietMs && sw.ElapsedMilliseconds >= MinHoldMs) break;
            }
            await Task.Delay(40);
        }
        Files.Log($"Fade: screen settled after {sw.ElapsedMilliseconds} ms (at {log.ElapsedMilliseconds} ms)");
    }

    private static byte[] Grid(Rectangle b)
    {
        using var full = new Bitmap(b.Width, b.Height, PixelFormat.Format32bppPArgb);
        using (var g = Graphics.FromImage(full)) g.CopyFromScreen(b.Location, Point.Empty, b.Size);
        using var small = new Bitmap(16, 10, PixelFormat.Format32bppPArgb);
        using (var g = Graphics.FromImage(small))
        {
            g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBilinear;
            g.DrawImage(full, new Rectangle(0, 0, 16, 10));
        }
        var r = new byte[160];
        for (var y = 0; y < 10; y++) for (var x = 0; x < 16; x++) { var c = small.GetPixel(x, y); r[y * 16 + x] = (byte)((c.R * 3 + c.G * 6 + c.B) / 10); }
        return r;
    }

    private sealed class Overlay : Form
    {
        private const int WS_EX_TOOLWINDOW = 0x80, WS_EX_NOACTIVATE = 0x08000000, WS_EX_TRANSPARENT = 0x20, WS_EX_LAYERED = 0x80000, WS_EX_TOPMOST = 0x8;
        private readonly Bitmap shot;
        private readonly Rectangle area;

        public Overlay(Bitmap shot, Rectangle area)
        {
            this.shot = shot;
            this.area = area;
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            AutoScaleMode = AutoScaleMode.None;
            TopMost = true;
            Bounds = area;
            BackgroundImage = shot;
            BackgroundImageLayout = ImageLayout.None;
            DoubleBuffered = true;
            Opacity = 0.999;   // stays a layered window the whole time, so changing opacity never repaints
        }

        protected override bool ShowWithoutActivation => true;

        protected override CreateParams CreateParams
        {
            get
            {
                var cp = base.CreateParams;
                cp.ExStyle |= WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT | WS_EX_LAYERED | WS_EX_TOPMOST;
                return cp;
            }
        }

        protected override void OnDpiChanged(DpiChangedEventArgs e)
        {
            e.Cancel = true;   // the picture is already in physical pixels
            base.OnDpiChanged(e);
        }

        public void ShowQuietly(IntPtr keepAbove)
        {
            Show();
            // Just under the panel (if it is open and on this screen), otherwise on top of everything.
            var panelHere = keepAbove != IntPtr.Zero && Native.GetWindowRect(keepAbove, out var pr)
                            && area.IntersectsWith(Rectangle.FromLTRB(pr.Left, pr.Top, pr.Right, pr.Bottom));
            Native.SetWindowPos(Handle, panelHere ? keepAbove : Native.HWND_TOPMOST, area.X, area.Y, area.Width, area.Height,
                                Native.SWP_NOACTIVATE | Native.SWP_SHOWWINDOW);
            Update();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) shot.Dispose();
            base.Dispose(disposing);
        }
    }
}
