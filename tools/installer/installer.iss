; PMA Aim Trainer's installer (Inno Setup 7), built by tools\build_installer.ps1. Installs for the
; current user only (no admin rights), with a Start menu entry and an uninstaller. Source 2 Viewer's
; command line tool comes along for importing the CS2 files; nothing from CS2 is in here. Settings,
; stats and imported CS2 files live in %APPDATA%\CS2AimTrainer and stay when uninstalling.

#define AppName "PMA Aim Trainer"
#define AppVersion "1.2.0"
#define Root "..\.."
#ifndef Source2Viewer
  #error Pass /DSource2Viewer=<folder with Source2Viewer-CLI.exe>
#endif

[Setup]
AppId={{F5321408-2705-44D8-99F3-7A662C50A8F3}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=PMA
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir={#Root}\build\installer
OutputBaseFilename=PMA-Aim-Trainer-Setup
SetupIconFile={#Root}\icon.ico
UninstallDisplayIcon={app}\{#AppName}.exe
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "swedish"; MessagesFile: "compiler:Languages\Swedish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#Root}\build\export\{#AppName}.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Root}\build\export\GODOT-LICENSE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Source2Viewer}\Source2Viewer-CLI.exe"; DestDir: "{app}\Source2Viewer"; Flags: ignoreversion
Source: "{#Source2Viewer}\*.dll"; DestDir: "{app}\Source2Viewer"; Flags: ignoreversion
Source: "Source2Viewer-LICENSE.txt"; DestDir: "{app}\Source2Viewer"; DestName: "LICENSE.txt"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppName}.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppName}.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppName}.exe"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
