#define MyAppName        "WDM"
#define MyAppVersion     "2.0.1"
#define MyAppSupportLink ""
#define MyAppAuthor      "WDM contributors; based on Brisk by Amin Beheshti"
#define CurrentYear      GetDateTimeString('yyyy','','')

[Setup]
AppId=B371DE77-37F4-4538-AE39-528F7C976A24
AppName={#MyAppName}
AppVersion={#MyAppVersion}

VersionInfoDescription={#MyAppName} installer
VersionInfoProductName={#MyAppName}
VersionInfoVersion={#MyAppVersion}

AppCopyright=(c) {#CurrentYear} {#MyAppAuthor}

UninstallDisplayName={#MyAppName} {#MyAppVersion}
UninstallDisplayIcon={app}\wdm.exe
AppPublisher=WDM contributors

WizardStyle=modern

ShowLanguageDialog=yes
UsePreviousLanguage=no
LanguageDetectionMethod=uilanguage

DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
OutputDir=OUTPUT_DIR
OutputBaseFilename=WDM_2.0_Alpha_Setup
SetupIconFile=SETUP_ICON_FILE
Compression=lzma
DisableDirPage=no
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "italian"; MessagesFile: "compiler:Languages\Italian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "autostart"; Description: "Launch WDM when I sign in"; GroupDescription: "Startup:"; Flags: unchecked

[Files]
Source: "BASE_DIR\build\windows\x64\runner\Release\wdm.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "BASE_DIR\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "BASE_DIR\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "BASE_DIR\extension\*"; DestDir: "{app}\extension"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "BASE_DIR\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "BASE_DIR\WDM-FORK-NOTICE.md"; DestDir: "{app}"; Flags: ignoreversion

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "WDM"; ValueData: """{app}\wdm.exe"" --from-startup"; Tasks: autostart; Flags: uninsdeletevalue

[Icons]
Name: "{autoprograms}\WDM"; Filename: "{app}\wdm.exe"
Name: "{autodesktop}\WDM"; Filename: "{app}\wdm.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\wdm.exe"; Description: "{cm:LaunchProgram,WDM}"; Flags: nowait postinstall skipifsilent
