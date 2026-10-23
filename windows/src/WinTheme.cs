using Kit;
using Microsoft.Win32;

namespace Nox;

/// <summary>
/// Switches Windows between light and dark: apps (AppsUseLightTheme) and the taskbar/Start
/// (SystemUsesLightTheme), then tells every open window with the "ImmersiveColorSet" broadcast.
/// </summary>
internal static class WinTheme
{
    public static bool IsDark() => SystemTheme.Read().apps;

    public static string? Set(bool dark)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(SystemTheme.PersonalizeKey, writable: true);
            var light = dark ? 0 : 1;
            key.SetValue("AppsUseLightTheme", light, RegistryValueKind.DWord);
            key.SetValue("SystemUsesLightTheme", light, RegistryValueKind.DWord);
        }
        catch (Exception ex)
        {
            Files.Log($"Theme write failed: {ex.Message}");
            return "Windows did not allow the theme change.";
        }
        // The broadcast waits on every top-level window in turn: keep it off the UI thread.
        _ = Task.Run(() =>
        {
            Native.SendMessageTimeout(Native.HWND_BROADCAST, Native.WM_SETTINGCHANGE, UIntPtr.Zero, "ImmersiveColorSet",
                                      Native.SMTO_ABORTIFHUNG, 1000, out _);
        });
        return null;
    }

    /// <summary>Is it "night" (dark time) at <paramref name="minute"/> after midnight?</summary>
    public static bool IsNight(int minute, int darkAt, int lightAt) =>
        darkAt > lightAt ? minute >= darkAt || minute < lightAt : minute >= darkAt && minute < lightAt;
}
