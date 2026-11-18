using System.Text.Json;

namespace HavalM6Setup;

internal sealed class AppSettings
{
    public string Serial { get; set; } = "";
    public string TimeZone { get; set; } = "Europe/Moscow";
    public int WindowX { get; set; } = -1;
    public int WindowY { get; set; } = -1;
    public int WindowWidth { get; set; } = 820;
    public int WindowHeight { get; set; } = 600;
}

internal static class SettingsManager
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true
    };

    public static AppSettings Load(string path)
    {
        try
        {
            if (!File.Exists(path)) return new AppSettings();
            return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(path), JsonOptions) ?? new AppSettings();
        }
        catch
        {
            return new AppSettings();
        }
    }

    public static void Save(string path, AppSettings settings)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path) ?? ".");
            File.WriteAllText(path, JsonSerializer.Serialize(settings, JsonOptions));
        }
        catch
        {
            // Настройки не критичны.
        }
    }
}
