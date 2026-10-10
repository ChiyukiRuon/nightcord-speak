; Stable AppId lets subsequent releases upgrade the same per-user installation.
#ifndef ProductVersion
  #error ProductVersion is required
#endif
#ifndef NumericVersion
  #error NumericVersion is required
#endif
#ifndef BundleDir
  #error BundleDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef InstallerAppId
  #define InstallerAppId "NightcordSpeak"
#endif

[Setup]
AppId={#InstallerAppId}
AppName=Nightcord Speak
AppVersion={#ProductVersion}
AppPublisher=ChiyukiRuon
AppPublisherURL=https://github.com/ChiyukiRuon/nightcord-speak
AppSupportURL=https://github.com/ChiyukiRuon/nightcord-speak/issues
DefaultDirName={localappdata}\Programs\Nightcord Speak
DefaultGroupName=Nightcord Speak
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=Nightcord-Speak-{#ProductVersion}-windows-x64-setup
SetupIconFile=..\apps\client\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Nightcord Speak.exe
VersionInfoVersion={#NumericVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
LanguageDetectionMethod=uilanguage
; Re-detect Windows' display language even after an older English-only install.
UsePreviousLanguage=no
ShowLanguageDialog=yes

[Languages]
; The first entry is the fallback for unsupported Windows display languages.
Name: english; MessagesFile: "compiler:Default.isl"
Name: chinesesimplified; MessagesFile: "installer-languages\ChineseSimplified.isl"
Name: chinesetraditional; MessagesFile: "installer-languages\ChineseTraditional.isl"
Name: japanese; MessagesFile: "compiler:Languages\Japanese.isl"
Name: korean; MessagesFile: "compiler:Languages\Korean.isl"

[Tasks]
Name: desktopicon; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,nightcord_client.exe,sounds\*"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Nightcord Speak"; Filename: "{app}\Nightcord Speak.exe"
Name: "{autodesktop}\Nightcord Speak"; Filename: "{app}\Nightcord Speak.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Nightcord Speak.exe"; Description: "{cm:LaunchProgram,Nightcord Speak}"; Flags: nowait postinstall skipifsilent

; Never recursively delete {app}: sound packs are user-owned files.
