# HAVAL M6 Setup

Репозиторий содержит два набора файлов:

- `windows/` — проект .NET 8 (WinForms, x64)
- `linux/` — набор shell-скриптов и сопутствующих файлов для Linux

## Windows

Сборка (требуется .NET 8 SDK):

```bash
cd windows
dotnet publish HAVAL_M6_SETUP.csproj -c Release -r win-x64 --self-contained true -o dist
```

Результат: `windows/dist/HAVAL_M6_SETUP.exe`

## Linux

Содержимое каталога `linux/` предназначено для использования в среде Linux x86_64.
