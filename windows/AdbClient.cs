using System.Diagnostics;

namespace HavalM6Setup;

internal sealed record AdbDevice(string Serial, string State, string Model, string Details)
{
    public string Display => string.IsNullOrWhiteSpace(Model) ? Serial : $"{Serial}  —  {Model}";
}

internal sealed record AdbResult(int ExitCode, string Output, string Error)
{
    public bool Ok => ExitCode == 0;
}

internal sealed class AdbClient : IDisposable
{
    private readonly string exe;
    private readonly bool dryRun;

    public string Serial { get; set; } = "";
    public bool DryRun => dryRun;

    public AdbClient(string executable, bool dryRun)
    {
        exe = executable;
        this.dryRun = dryRun;
    }

    public AdbResult Run(params string[] args)
    {
        if (dryRun) return new AdbResult(0, "[dry-run] " + string.Join(' ', args), "");
        if (!File.Exists(exe)) throw new FileNotFoundException("adb.exe не найден", exe);

        var psi = new ProcessStartInfo(exe)
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };
        psi.Environment["ANDROID_SDK_HOME"] = Path.GetDirectoryName(exe) ?? "";
        psi.Environment["HOME"] = Path.GetDirectoryName(exe) ?? "";
        foreach (var arg in args) psi.ArgumentList.Add(arg);

        using var process = new Process { StartInfo = psi };
        process.Start();

        var outputTask = process.StandardOutput.ReadToEndAsync();
        var errorTask = process.StandardError.ReadToEndAsync();

        if (!process.WaitForExit(120000))
        {
            try { process.Kill(true); } catch { }
            throw new TimeoutException("ADB не ответил за 120 секунд: " + string.Join(' ', args));
        }

        Task.WaitAll(outputTask, errorTask);
        return new AdbResult(
            process.ExitCode,
            outputTask.Result.Replace("\r", ""),
            errorTask.Result.Replace("\r", ""));
    }

    public AdbResult Device(params string[] args) => Run(new[] { "-s", Serial }.Concat(args).ToArray());

    public AdbResult Target(string serial, params string[] args) => Run(new[] { "-s", serial }.Concat(args).ToArray());

    public List<AdbDevice> Devices()
    {
        var result = Run("devices", "-l");
        if (!result.Ok) throw new InvalidOperationException(result.Error);

        var list = new List<AdbDevice>();
        foreach (var line in result.Output.Split('\n', StringSplitOptions.RemoveEmptyEntries).Skip(1))
        {
            var parts = line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 0) continue;
            var model = parts.FirstOrDefault(x => x.StartsWith("model:", StringComparison.OrdinalIgnoreCase))?[6..] ?? "";
            list.Add(new AdbDevice(parts[0], parts.Length > 1 ? parts[1] : "", model, line));
        }
        return list;
    }

    public string Shell(string command)
    {
        var result = Device("shell", command);
        if (!result.Ok) throw new InvalidOperationException(FirstError(result, command));
        return result.Output.Trim();
    }

    public bool ShellTry(string command, out string output)
    {
        var result = Device("shell", command);
        output = (result.Output + result.Error).Trim();
        return result.Ok;
    }

    public void Dispose()
    {
        if (dryRun) return;
        try { Run("kill-server"); } catch { }
    }

    private static string FirstError(AdbResult result, string command) =>
        string.IsNullOrWhiteSpace(result.Error) ? $"ADB-команда не выполнилась: {command}" : result.Error.Trim();
}
