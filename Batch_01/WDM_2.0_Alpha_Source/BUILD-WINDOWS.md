# Build WDM 2 alpha on Windows

This is source code, **not a validated Windows release**. Use a Windows 10/11 x64 development PC with Flutter (Windows desktop support), Visual Studio with Desktop development with C++, PowerShell, Git, and Inno Setup 6. Install Flutter's dependencies with `flutter doctor -v` before building. The `extension/` folder is a Chrome/Edge/Brave Manifest V3 extension; install it using Extensions > Developer mode > Load unpacked.

From this folder in PowerShell:

```powershell
flutter pub get
flutter build windows --release
# Run only after the build succeeds:
.\scripts\build-windows-installer.ps1
```

The script checks the actual `build/windows/x64/runner/Release/wdm.exe`, creates the installer under `dist/`, and includes the browser extension and GPL notice. The optional installer task writes a per-user `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` entry. WDM uses port 3021 by default, leaving Brisk's default port alone.

Verify on a clean Windows test account: install, launch, toggle light/dark and restart, add a regular download, send a media link from the unpacked extension, test pause/resume, then uninstall and check the optional autostart entry is gone. Do not distribute as a stable release until these tests pass. Never rename the previous WDM 1.4.1 installer to WDM 2.
