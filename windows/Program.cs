using System.Windows.Forms;

namespace HavalM6Setup;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        var options = Options.Parse(args);

        if (options.CommandLine)
        {
            NativeConsole.Attach();
            Console.OutputEncoding = System.Text.Encoding.UTF8;
        }

        using var app = new SetupApp(options);
        if (options.CommandLine)
        {
            Environment.ExitCode = app.RunCli();
            return;
        }

        Application.Run(new MainForm(app));
    }
}

internal sealed record Options(
    string? Command,
    bool Yes,
    bool Full,
    string Serial,
    string TimeZone,
    bool NoTime,
    bool DryRun)
{
    public bool CommandLine => Command is not null;

    public static Options Parse(string[] args)
    {
        string? command = null;
        var serial = "";
        var tz = "Europe/Moscow";
        var yes = false;
        var full = false;
        var noTime = false;
        var dry = false;

        for (var i = 0; i < args.Length; i++)
        {
            var raw = args[i];
            var arg = raw.ToLowerInvariant();
            string? inlineValue = null;
            var eq = arg.IndexOf('=');
            if (eq > 0)
            {
                inlineValue = raw[(eq + 1)..];
                arg = arg[..eq];
            }

            string NextValue()
            {
                if (inlineValue is not null) return inlineValue;
                if (i + 1 < args.Length) return args[++i];
                throw new ArgumentException($"Для параметра {raw} нужно значение");
            }

            switch (arg)
            {
                case "--install": command = "install"; break;
                case "--check": command = "check"; break;
                case "--rollback": command = "rollback"; break;
                case "--yes": yes = true; break;
                case "--full": full = true; break;
                case "--no-time": noTime = true; break;
                case "--dry-run": dry = true; break;
                case "--serial": serial = NextValue(); break;
                case "--tz": tz = NextValue(); break;
            }
        }

        return new Options(command, yes, full, serial, tz, noTime, dry);
    }

    public static string Usage() =>
        "HAVAL_M6_SETUP [--install --yes] [--check] [--rollback [--full]] " +
        "[--serial <serial>] [--tz <timezone>] [--no-time] [--dry-run]";
}
