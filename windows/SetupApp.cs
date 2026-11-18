using System.Reflection;
using System.Security.Cryptography;

namespace HavalM6Setup;

internal sealed class SetupApp : IDisposable
{
    private sealed record Payload(string Resource, string File, string ManifestPath);

    private static readonly Payload[] Payloads =
    {
        new("HAVAL_M6_SETUP.adb.exe", "adb.exe", "tools/adb.exe"),
        new("HAVAL_M6_SETUP.AdbWinApi.dll", "AdbWinApi.dll", "tools/AdbWinApi.dll"),
        new("HAVAL_M6_SETUP.AdbWinUsbApi.dll", "AdbWinUsbApi.dll", "tools/AdbWinUsbApi.dll"),
        new("HAVAL_M6_SETUP.havalm6-launcher.apk", "havalm6-launcher.apk", "apk/havalm6-launcher.apk"),
        new("HAVAL_M6_SETUP.YandexMusicLite-v1.14.8.apk", "YandexMusicLite-v1.14.8.apk", "apk/YandexMusicLite-v1.14.8.apk"),
    };

    public Options Options { get; set; }
    public AdbClient Adb { get; }
    public string Root { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "HAVAL_M6_SETUP");

    public string SettingsPath => Path.Combine(Root, "settings.json");

    public SetupApp(Options options)
    {
        Options = options;
        Adb = new AdbClient(Path.Combine(Root, "adb.exe"), options.DryRun)
        {
            Serial = options.Serial
        };
    }

    public void PrepareResources()
    {
        Directory.CreateDirectory(Root);
        var sums = ReadManifest();

        foreach (var payload in Payloads)
        {
            if (!sums.TryGetValue(payload.ManifestPath, out var expected))
                throw new InvalidDataException($"В SHA256SUMS.txt нет записи для {payload.ManifestPath}");

            var bytes = ReadResource(payload.Resource);
            var actual = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
            if (!actual.Equals(expected, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException($"Встроенный файл повреждён: {payload.File}");

            var path = Path.Combine(Root, payload.File);
            if (File.Exists(path) && FileMatches(path, expected))
                continue;

            File.WriteAllBytes(path, bytes);
        }

        var manifestPath = Path.Combine(Root, "SHA256SUMS.txt");
        var manifestBytes = ReadResource("HAVAL_M6_SETUP.SHA256SUMS.txt");
        if (!File.Exists(manifestPath) || !File.ReadAllBytes(manifestPath).SequenceEqual(manifestBytes))
            File.WriteAllBytes(manifestPath, manifestBytes);
    }

    public void VerifyPayload(Action<string> log)
    {
        var sums = ReadManifest();
        foreach (var payload in Payloads)
        {
            var path = Path.Combine(Root, payload.File);
            if (!File.Exists(path))
                throw new FileNotFoundException("Не найден файл payload", path);

            if (!FileMatches(path, sums[payload.ManifestPath]))
                throw new InvalidDataException($"SHA-256 не совпал: {payload.File}");

            log($"SHA-256 OK: {payload.File}");
        }
    }

    public int RunCli()
    {
        try
        {
            Console.WriteLine(Options.Usage());
            PrepareResources();
            return Options.Command switch
            {
                "check" => Workflow.Check(Adb, Console.WriteLine),
                "install" => Workflow.Install(this, Console.WriteLine),
                "rollback" => Workflow.Rollback(this, Console.WriteLine),
                _ => 2
            };
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("ОШИБКА: " + ex.Message);
            return 1;
        }
    }

    private static byte[] ReadResource(string name)
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(name)
            ?? throw new FileNotFoundException($"Не найден ресурс {name}");
        using var memory = new MemoryStream();
        stream.CopyTo(memory);
        return memory.ToArray();
    }

    private Dictionary<string, string> ReadManifest()
    {
        var content = System.Text.Encoding.UTF8.GetString(ReadResource("HAVAL_M6_SETUP.SHA256SUMS.txt"));
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var line in content.Split('\n', StringSplitOptions.RemoveEmptyEntries))
        {
            var parts = line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length >= 2)
                result[parts[1].Replace('\\', '/')] = parts[0];
        }
        return result;
    }

    private static bool FileMatches(string path, string expected)
    {
        if (!File.Exists(path)) return false;
        var actual = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))).ToLowerInvariant();
        return actual.Equals(expected, StringComparison.OrdinalIgnoreCase);
    }

    public void Dispose() => Adb.Dispose();
}
