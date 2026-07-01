; Inno Setup Script for ScoringNidra-lite
[Setup]
AppId={{D1A39B10-E24F-465B-B91C-7B9F01194F66}
AppName=ScoringNidra-lite
AppVersion=1.2.0
DefaultDirName={userappdata}\ScoringNidra-lite
DefaultGroupName=ScoringNidra-lite
OutputDir=..\dist
OutputBaseFilename=ScoringNidra-lite-Installer
SetupIconFile=runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\ScoringNidra-lite"; Filename: "{app}\ScoringNidra.exe"
Name: "{autodesktop}\ScoringNidra-lite"; Filename: "{app}\ScoringNidra.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\ScoringNidra.exe"; Description: "{cm:LaunchProgram,ScoringNidra-lite}"; Flags: nowait postinstall skipifsilent
