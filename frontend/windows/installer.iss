; Inno Setup Script for ScoringNidra
[Setup]
AppId={{C6D29A10-D24E-464A-A91B-6B8F01184F65}
AppName=ScoringNidra
AppVersion=1.0.0
DefaultDirName={userappdata}\ScoringNidra
DefaultGroupName=ScoringNidra
OutputDir=..\dist
OutputBaseFilename=ScoringNidra-Installer
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
Name: "{group}\ScoringNidra"; Filename: "{app}\ScoringNidra.exe"
Name: "{autodesktop}\ScoringNidra"; Filename: "{app}\ScoringNidra.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\ScoringNidra.exe"; Description: "{cm:LaunchProgram,ScoringNidra}"; Flags: nowait postinstall skipifsilent
