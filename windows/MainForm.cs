using System.Drawing;
using System.Windows.Forms;

namespace HavalM6Setup;

internal sealed class MainForm : Form
{
    private readonly SetupApp app;
    private readonly AppSettings settings;
    private readonly TextBox log = new();
    private readonly CheckBox agree = new();
    private readonly CheckBox fullRollback = new();
    private readonly Button install = new();
    private readonly Button check = new();
    private readonly Button rollback = new();
    private readonly Label deviceLabel = new();

    public MainForm(SetupApp application)
    {
        app = application;
        settings = SettingsManager.Load(app.SettingsPath);

        Text = "HAVAL M6 Setup";
        MinimumSize = new Size(820, 580);
        Size = new Size(settings.WindowWidth, settings.WindowHeight);
        StartPosition = FormStartPosition.Manual;
        if (settings.WindowX >= 0 && settings.WindowY >= 0)
            Location = new Point(settings.WindowX, settings.WindowY);
        else
            StartPosition = FormStartPosition.CenterScreen;

        var header = new Label
        {
            Text = "HAVAL M6 — установка приложений и настроек",
            Dock = DockStyle.Top,
            Height = 46,
            Font = new Font("Segoe UI", 14, FontStyle.Bold),
            Padding = new Padding(14, 10, 0, 0)
        };

        var info = new Label
        {
            Text =
                "Что делает установка:\n" +
                "• ставит лаунчер HAVAL M6 и Yandex Music Lite (/-r сохраняет данные приложений);\n" +
                "• снимает фильтр Adayo и назначает наш лаунчер домашним экраном;\n" +
                "• штатные лаунчер и радио только pm disable-user, без удаления;\n" +
                "• включает доступ лаунчера к уведомлениям;\n" +
                "• ставит зону и время через вендорский сервис adayo.setting;\n" +
                "• повторный запуск сверяет SHA-256 и перезаписывает только расхождения.",
            Dock = DockStyle.Top,
            AutoSize = true,
            MaximumSize = new Size(int.MaxValue, 150),
            Padding = new Padding(14, 8, 14, 4),
            Font = new Font("Segoe UI", 9)
        };

        agree.Text = "Действия обратимы, но выполняются на мой риск; дилер теоретически может заметить сторонний APK.";
        agree.AutoSize = true;
        agree.Dock = DockStyle.Top;
        agree.Padding = new Padding(14, 4, 8, 4);
        agree.Checked = true;

        fullRollback.Text = "Полный откат (удалить наши APK)";
        fullRollback.AutoSize = true;
        fullRollback.Dock = DockStyle.Top;
        fullRollback.Padding = new Padding(14, 0, 8, 4);

        deviceLabel.Text = "Устройство: не выбрано";
        deviceLabel.Dock = DockStyle.Top;
        deviceLabel.Height = 28;
        deviceLabel.Padding = new Padding(14, 6, 0, 0);
        deviceLabel.Font = new Font("Segoe UI", 9, FontStyle.Italic);

        var buttons = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            Height = 52,
            Padding = new Padding(10, 8, 10, 6)
        };
        Configure(install, "Установить");
        Configure(check, "Проверить");
        Configure(rollback, "Откат");
        buttons.Controls.AddRange(new Control[] { install, check, rollback });

        log.Multiline = true;
        log.ReadOnly = true;
        log.ScrollBars = ScrollBars.Vertical;
        log.Dock = DockStyle.Fill;
        log.Font = new Font("Consolas", 9);
        log.BackColor = Color.FromArgb(245, 245, 245);
        log.Padding = new Padding(8);

        Controls.Add(log);
        Controls.Add(buttons);
        Controls.Add(deviceLabel);
        Controls.Add(fullRollback);
        Controls.Add(agree);
        Controls.Add(info);
        Controls.Add(header);

        install.Click += async (_, _) => await Run("install", () => Workflow.Install(app, Write));
        check.Click += async (_, _) => await Run("check", () => Workflow.Check(app.Adb, Write));
        rollback.Click += async (_, _) => await Run("rollback", () => Workflow.Rollback(app, Write));

        FormClosing += (_, _) =>
        {
            settings.Serial = app.Adb.Serial;
            settings.TimeZone = app.Options.TimeZone;
            if (WindowState == FormWindowState.Normal)
            {
                settings.WindowX = Location.X;
                settings.WindowY = Location.Y;
                settings.WindowWidth = Width;
                settings.WindowHeight = Height;
            }
            SettingsManager.Save(app.SettingsPath, settings);
        };

        if (!string.IsNullOrWhiteSpace(app.Options.Serial)) app.Adb.Serial = app.Options.Serial;
        else app.Adb.Serial = settings.Serial;
        app.Options = app.Options with { TimeZone = string.IsNullOrWhiteSpace(settings.TimeZone) ? app.Options.TimeZone : settings.TimeZone };

        Write("Готово к работе. Подключите ГУ кабелем с передачей данных и подтвердите RSA на экране магнитолы.");
    }

    private static void Configure(Button button, string text)
    {
        button.Text = text;
        button.Width = 150;
        button.Height = 34;
        button.Font = new Font("Segoe UI", 9, FontStyle.Bold);
    }

    private async Task Run(string operation, Func<int> action)
    {
        if (operation == "install" && !agree.Checked)
        {
            Write("Перед установкой подтвердите предупреждение.");
            return;
        }

        try
        {
            app.PrepareResources();
            var device = PickDevice();
            if (device is null) return;
            app.Adb.Serial = device.Serial;
            deviceLabel.Text = "Устройство: " + device.Display;
            settings.Serial = device.Serial;

            app.Options = app.Options with
            {
                Yes = operation is "install" or "rollback",
                Full = fullRollback.Checked
            };

            Toggle(false);
            log.Clear();
            await Task.Run(action);
            Write("Готово.");
        }
        catch (Exception ex)
        {
            Write("ОШИБКА: " + ex.Message);
        }
        finally
        {
            Toggle(true);
        }
    }

    private AdbDevice? PickDevice()
    {
        try
        {
            app.Adb.Run("start-server");
            var devices = app.Adb.Devices().Where(d => d.State == "device").ToList();
            if (devices.Count == 0)
                throw new InvalidOperationException("ADB-устройство не найдено. Проверьте кабель, «Отладку по USB» и подтверждение RSA.");

            if (devices.Count == 1) return devices[0];

            using var form = new Form
            {
                Text = "Выберите устройство",
                Width = 520,
                Height = 210,
                StartPosition = FormStartPosition.CenterParent,
                MinimizeBox = false,
                MaximizeBox = false
            };

            var label = new Label
            {
                Text = "Подключено несколько ADB-устройств. Выберите головное устройство:",
                Dock = DockStyle.Top,
                Height = 42,
                Padding = new Padding(12, 10, 12, 0)
            };
            var combo = new ComboBox
            {
                Dock = DockStyle.Top,
                DropDownStyle = ComboBoxStyle.DropDownList,
                Margin = new Padding(12)
            };
            combo.Items.AddRange(devices.Select(d => (object)d.Display).ToArray());
            var savedIndex = devices.FindIndex(d => d.Serial == app.Adb.Serial);
            combo.SelectedIndex = savedIndex >= 0 ? savedIndex : 0;

            var ok = new Button { Text = "Выбрать", DialogResult = DialogResult.OK, Dock = DockStyle.Bottom, Height = 38 };
            var cancel = new Button { Text = "Отмена", DialogResult = DialogResult.Cancel, Dock = DockStyle.Bottom, Height = 38 };
            var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 48, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(10, 6, 10, 0) };
            buttons.Controls.AddRange(new Control[] { cancel, ok });

            form.Controls.Add(combo);
            form.Controls.Add(label);
            form.Controls.Add(buttons);
            form.CancelButton = cancel;
            form.AcceptButton = ok;

            return form.ShowDialog(this) == DialogResult.OK ? devices[combo.SelectedIndex] : null;
        }
        catch (Exception ex)
        {
            Write("ОШИБКА: " + ex.Message);
            return null;
        }
    }

    private void Toggle(bool enabled)
    {
        install.Enabled = enabled;
        check.Enabled = enabled;
        rollback.Enabled = enabled;
    }

    private void Write(string text)
    {
        if (InvokeRequired)
        {
            BeginInvoke(() => Write(text));
            return;
        }
        log.AppendText(text + Environment.NewLine);
        log.SelectionStart = log.TextLength;
        log.ScrollToCaret();
    }
}
