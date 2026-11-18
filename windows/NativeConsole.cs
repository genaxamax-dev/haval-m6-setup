using System.Runtime.InteropServices;

namespace HavalM6Setup;

internal static class NativeConsole
{
    private const int AttachParentProcess = -1;

    public static void Attach()
    {
        try
        {
            if (!AttachConsole(AttachParentProcess))
                _ = AllocConsole();
            _ = SetConsoleOutputCP(65001);
        }
        catch
        {
            // GUI-режим без консоли: игнорируем.
        }
    }

    [DllImport("kernel32.dll")]
    private static extern bool AttachConsole(int processId);

    [DllImport("kernel32.dll")]
    private static extern bool AllocConsole();

    [DllImport("kernel32.dll")]
    private static extern bool SetConsoleOutputCP(uint codePage);
}
