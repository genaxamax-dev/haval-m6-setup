using System.Text.RegularExpressions;

namespace HavalM6Setup;

internal static class Workflow
{
    private const string Pkg = "com.aistudio.havalm6launcher.kqtxzn";
    private const string DefaultAct = Pkg + "/com.example.MainActivity";
    private const string Lite = "YandexMusicLite.KorenskoyR";
    private const string Listener = Pkg + "/com.example.media.YandexNotificationListener";
    private const string Radio = "com.adayo.ora.radio";
    private const string Stock = "com.adayo.launcher";
    private const string DefaultStockAct = Stock + "/.ui.Launcher_MainActivity";
    private static readonly string[] OtherHomePackages = { "org.fossify.home" };

    public static int Check(AdbClient adb, Action<string> log)
    {
        Select(adb, log);

        var checks = new (string Title, string Command)[]
        {
            ("Модель", "getprop ro.product.model"),
            ("Android", "getprop ro.build.version.release + ' (API ' + getprop ro.build.version.sdk + ')'"),
            ("Сборка", "getprop ro.build.display.id"),
            ("HOME", "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME"),
            ("Лаунчер", $"pm path {Pkg}"),
            ("Lite", $"pm path {Lite}"),
            ("Радио", $"dumpsys package {Radio} | grep 'User 0:'"),
            ("Уведомления", "settings get secure enabled_notification_listeners"),
            ("Зона", "getprop persist.sys.timezone"),
            ("Время", "date")
        };

        foreach (var (title, command) in checks)
            log($"{title}: {SafeShell(adb, command)}");

        return 0;
    }

    public static int Install(SetupApp app, Action<string> log)
    {
        var adb = app.Adb;
        app.VerifyPayload(log);
        Select(adb, log);

        log("\n== Root ==");
        var rootResult = adb.Run("root");
        log(rootResult.Output.Trim());
        adb.Run("wait-for-device");
        var uid = adb.Shell("id");
        log(uid);
        var rooted = uid.Contains("uid=0", StringComparison.Ordinal);
        if (!rooted) log("ВНИМАНИЕ: root не получен. Установка продолжится, но время может не встать.");

        log("\n== Установка приложений ==");
        InstallApk(adb, Path.Combine(app.Root, "havalm6-launcher.apk"), Pkg, "лаунчер HAVAL M6", log);
        InstallApk(adb, Path.Combine(app.Root, "YandexMusicLite-v1.14.8.apk"), Lite, "Yandex Music Lite", log);

        log("\n== Домашний экран ==");
        var activity = ResolveActivity(adb, $"dumpsys package {Pkg}", Pkg, DefaultAct);
        var setHomeOk = TryShell(adb, $"cmd package set-home-activity {activity}", out var setHomeOut);
        log("Назначение HOME: " + Short(setHomeOut, setHomeOk ? "OK" : "не удалось"));

        var homeNow = SafeShell(adb, "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME");
        log("Сейчас HOME: " + Short(homeNow));

        if (homeNow.Contains(activity, StringComparison.OrdinalIgnoreCase))
        {
            foreach (var homePkg in new[] { Stock }.Concat(OtherHomePackages))
            {
                if (!PackageInstalled(adb, homePkg)) continue;
                TryShell(adb, $"pm disable-user --user 0 {homePkg}", out _);
                TryShell(adb, $"am force-stop {homePkg}", out _);
                log($"Отключён домашний экран: {homePkg}");
            }
        }
        else
        {
            log("ВНИМАНИЕ: HOME не указывает на наш лаунчер. Штатный лаунчер не отключаю.");
        }

        log("\n== Штатное радио ==");
        TryShell(adb, $"pm disable-user --user 0 {Radio}", out _);
        TryShell(adb, $"am force-stop {Radio}", out _);
        log("Радио: " + Short(SafeShell(adb, $"dumpsys package {Radio} | grep 'User 0:'"), "состояние неизвестно"));

        log("\n== Доступ к уведомлениям ==");
        EnableNotifications(adb, log);

        log("\n== Запуск лаунчера ==");
        TryShell(adb, $"am start -n {activity}", out var startOut);
        log(Short(startOut, "OK"));

        if (!app.Options.NoTime)
        {
            if (rooted) SetTime(adb, app.Options.TimeZone, log);
            else log("\nВНИМАНИЕ: без root время не установлено.");
        }
        else
        {
            log("\nВремя пропущено (--no-time).");
        }

        log("\nГОТОВО. Перезагрузка НЕ выполнялась.");
        return 0;
    }

    public static int Rollback(SetupApp app, Action<string> log)
    {
        var adb = app.Adb;
        Select(adb, log);

        log("\n== Root ==");
        log(adb.Run("root").Output.Trim());
        adb.Run("wait-for-device");

        log("\n== Возврат штатного лаунчера ==");
        var stockFound = PackageInstalled(adb, Stock);
        if (stockFound)
        {
            TryShell(adb, $"pm enable {Stock}", out _);
            var stockActivity = ResolveActivity(adb, $"dumpsys package {Stock}", Stock, DefaultStockAct);
            TryShell(adb, $"cmd package set-home-activity {stockActivity}", out var outStock);
            log("HOME: " + Short(outStock, stockActivity));
        }
        else
        {
            log("Штатный лаунчер не найден — HOME не меняю.");
        }

        foreach (var homePkg in OtherHomePackages)
            if (PackageInstalled(adb, homePkg)) TryShell(adb, $"pm enable {homePkg}", out _);

        log("\n== Возврат радио ==");
        TryShell(adb, $"pm enable {Radio}", out _);
        log("Радио: " + Short(SafeShell(adb, $"dumpsys package {Radio} | grep 'User 0:'"), "состояние неизвестно"));

        log("\n== Снятие доступа к уведомлениям ==");
        TryShell(adb, $"cmd notification disallow_listener {Listener}", out _);
        log("OK");

        if (app.Options.Full)
        {
            if (stockFound)
            {
                log("\n== Полный откат: удаление приложений ==");
                TryShell(adb, $"am force-stop {Pkg}", out _);
                TryShell(adb, $"am force-stop {Lite}", out _);
                AdbStep(adb, log, "Удаление лаунчера", false, "uninstall", Pkg);
                AdbStep(adb, log, "Удаление Lite", false, "uninstall", Lite);
            }
            else
            {
                log("\nПОЛНЫЙ ОТКАТ ОТКЛОНЁН: штатный лаунчер не найден, наш удалять нельзя.");
            }
        }

        TryShell(adb, "input keyevent KEYCODE_HOME", out _);
        log("\nОткат выполнен. Время и часовой пояс не менялись.");
        return 0;
    }

    private static void Select(AdbClient adb, Action<string> log)
    {
        adb.Run("start-server");
        var devices = adb.Devices().Where(d => d.State == "device").ToList();
        if (devices.Count == 0)
            throw new InvalidOperationException(
                "ADB-устройство не найдено. Проверьте кабель с передачей данных, «Отладку по USB» и подтверждение RSA на ГУ.");

        AdbDevice selected;
        if (!string.IsNullOrWhiteSpace(adb.Serial))
        {
            selected = devices.FirstOrDefault(d => d.Serial == adb.Serial)
                ?? throw new InvalidOperationException($"Устройство {adb.Serial} сейчас не подключено.");
        }
        else if (devices.Count > 1)
        {
            throw new InvalidOperationException("Подключено несколько устройств. Выберите одно в GUI или укажите --serial <serial>.");
        }
        else
        {
            selected = devices[0];
        }

        adb.Serial = selected.Serial;
        var model = adb.Shell("getprop ro.product.model");
        var sdk = adb.Shell("getprop ro.build.version.sdk");
        log($"Устройство: {selected.Serial} | модель {model} | API {sdk}");
        if (sdk != "28") log("ВНИМАНИЕ: ожидался Android 9 / API 28.");
        if (model is not ("MEK-MX8Q" or "mek_8q_car"))
            log("ВНИМАНИЕ: модель не MEK-MX8Q/mek_8q_car.");
    }

    private static void InstallApk(AdbClient adb, string path, string package, string title, Action<string> log)
    {
        var filter = adb.Shell("service call package 195 i32 1");
        if (!filter.StartsWith("Result:", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException($"Не удалось снять фильтр Adayo: {Short(filter)}");
        log($"Фильтр Adayo снят: {Short(filter)}");

        var result = adb.Device("install", "-r", "-g", path);
        log($"Установка {title}: {Short(result.Output + result.Error)}");
        if (!result.Ok) throw new InvalidOperationException($"Не удалось установить {title}");

        var installed = adb.Shell($"pm path {package}");
        if (string.IsNullOrWhiteSpace(installed))
            throw new InvalidOperationException($"{package} не найден после установки");
        log($"Проверка пакета: {Short(installed)}");
    }

    private static void EnableNotifications(AdbClient adb, Action<string> log)
    {
        TryShell(adb, $"cmd notification allow_listener {Listener}", out _);
        var current = SafeShell(adb, "settings get secure enabled_notification_listeners");
        if (current.Contains(Listener, StringComparison.OrdinalIgnoreCase))
        {
            log("Доступ к уведомлениям включён.");
            return;
        }

        var parts = current
            .Split(':', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(x => x is not ("null" or ""))
            .ToList();
        if (!parts.Contains(Listener, StringComparer.OrdinalIgnoreCase)) parts.Add(Listener);
        TryShell(adb, $"settings put secure enabled_notification_listeners {string.Join(':', parts)}", out _);

        var after = SafeShell(adb, "settings get secure enabled_notification_listeners");
        if (after.Contains(Listener, StringComparison.OrdinalIgnoreCase)) log("Доступ к уведомлениям включён (fallback).");
        else log("ВНИМАНИЕ: доступ к уведомлениям включить не удалось. Включите вручную в настройках ГУ.");
    }

    private static void SetTime(AdbClient adb, string timeZone, Action<string> log)
    {
        log("\n== Время и часовой пояс ==");
        TimeZoneInfo zone;
        try
        {
            zone = TimeZoneInfo.FindSystemTimeZoneById(timeZone);
        }
        catch
        {
            log($"ВНИМАНИЕ: зона {timeZone} не найдена, используется локальное время ПК.");
            zone = TimeZoneInfo.Local;
        }

        var when = TimeZoneInfo.ConvertTime(DateTime.UtcNow.AddSeconds(5), zone);
        ShellStep(adb, log, "Зона", $"service call adayo.setting 13 i32 0 i32 1 s16 {timeZone} i32 0");
        ShellStep(adb, log, "Дата и время",
            $"service call adayo.setting 18 i32 0 i32 6 " +
            $"s16 {when.Year} s16 {when.Month} s16 {when.Day} " +
            $"s16 {when.Hour} s16 {when.Minute} s16 {when.Second} i32 0");

        var expectedYear = when.Year.ToString();
        log("Ожидание синхронизации MCU: 70 секунд...");
        if (adb.DryRun) return;
        Thread.Sleep(TimeSpan.FromSeconds(70));
        var after = SafeShell(adb, "date");
        log("После проверки: " + Short(after));
        if (!after.Contains(expectedYear, StringComparison.Ordinal))
            log("ВНИМАНИЕ: время откатилось — MCU не принял команду. Повторите установку времени.");
        else
            log("Время держится.");
    }

    private static bool PackageInstalled(AdbClient adb, string package) =>
        adb.Shell($"pm list packages {package}").Contains("package:" + package, StringComparison.OrdinalIgnoreCase);

    private static string ResolveActivity(AdbClient adb, string dumpsCommand, string package, string fallback)
    {
        var dumps = SafeShell(adb, dumpsCommand);
        if (dumps.Contains(fallback, StringComparison.OrdinalIgnoreCase)) return fallback;

        var pattern = Regex.Escape(package) + @"/[A-Za-z0-9_.]+";
        foreach (Match match in Regex.Matches(dumps, pattern))
        {
            var value = match.Value;
            if (value.Contains("Receiver", StringComparison.OrdinalIgnoreCase) ||
                value.Contains("Provider", StringComparison.OrdinalIgnoreCase) ||
                value.Contains("Service", StringComparison.OrdinalIgnoreCase))
                continue;
            return value;
        }
        return fallback;
    }

    private static void ShellStep(AdbClient adb, Action<string> log, string title, string command)
    {
        var ok = adb.ShellTry(command, out var output);
        log($"{title}: {Short(output, ok ? "OK" : "не удалось")}");
        if (!ok) throw new InvalidOperationException($"{title}: {output}");
    }

    private static bool TryShell(AdbClient adb, string command, out string output) => adb.ShellTry(command, out output);

    private static void AdbStep(AdbClient adb, Action<string> log, string title, bool throwOnError, params string[] args)
    {
        var result = adb.Device(args);
        log($"{title}: {Short(result.Output + result.Error, result.Ok ? "OK" : "ошибка")}");
        if (!result.Ok && throwOnError) throw new InvalidOperationException($"{title}: {result.Error}");
    }

    private static string SafeShell(AdbClient adb, string command)
    {
        try { return adb.Shell(command); }
        catch { return ""; }
    }

    private static string Short(string value, string empty = "")
    {
        value = value.Trim();
        if (value.Length == 0) return empty;
        return value.Length <= 600 ? value : value[..600] + "…";
    }
}
