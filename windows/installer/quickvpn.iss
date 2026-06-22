; Inno Setup script for QuickVPN.
;
; Driven by scripts/make_win.ps1, which passes AppVersion, ReleaseDir (the
; Flutter Release output folder), and RepoRoot. Compile manually with, e.g.:
;   iscc /DAppVersion=1.0.0 /DReleaseDir=...\Release /DRepoRoot=..\.. windows\installer\quickvpn.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef ReleaseDir
  #define ReleaseDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef RepoRoot
  #define RepoRoot "..\.."
#endif

[Setup]
AppName=QuickVPN
AppVersion={#AppVersion}
AppPublisher=refactorroom.com
DefaultDirName={autopf}\QuickVPN
DefaultGroupName=QuickVPN
DisableProgramGroupPage=yes
OutputDir={#RepoRoot}\build
OutputBaseFilename=quickvpn-v{#AppVersion}-windows-x64-setup
SetupIconFile={#RepoRoot}\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\quickvpn.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs

[Icons]
Name: "{group}\QuickVPN"; Filename: "{app}\quickvpn.exe"
Name: "{autodesktop}\QuickVPN"; Filename: "{app}\quickvpn.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Run]
Filename: "{app}\quickvpn.exe"; Description: "Launch QuickVPN"; Flags: nowait postinstall skipifsilent
