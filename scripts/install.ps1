# Fetch the latest version from GitHub API
try {
    $LatestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/Ajatt-Tools/mpvacious/releases/latest" -ErrorAction Stop
    $LatestVersion = $LatestRelease.tag_name
    $ZipURL = "https://github.com/Ajatt-Tools/mpvacious/releases/latest/download/mpvacious_$LatestVersion.zip"
} catch {
    # Abort if API request fails since we don't know URL to zip
    Write-Output "Error: Couldn't fetch the latest version from GitHub API."
    Write-Output "Aborting!"
    Exit 1
}
$ConfURL = "https://github.com/Ajatt-Tools/mpvacious/releases/latest/download/subs2srs.conf"
$Files = "scripts/mpvacious", "scripts/subs2srs"

# Determine install directory
if (Test-Path env:MPV_CONFIG_DIR) {
	Write-Output "Installing into (MPV_CONFIG_DIR):"
	$ConfigDir = "$env:MPV_CONFIG_DIR"
}
elseif (Test-Path "$PWD/portable_config") {
	Write-Output "Installing into (portable config):"
	$ConfigDir = "$PWD/portable_config"
}
elseif ((Get-Item -Path $PWD).BaseName -eq "portable_config") {
	Write-Output "Installing into (portable config):"
	$ConfigDir = "$PWD"
}
else {
	Write-Output "Installing into (current user config):"
	$ConfigDir = "$env:APPDATA/mpv"
	if (!(Test-Path $ConfigDir)) {
		Write-Output "Creating folder: $ConfigDir"
		New-Item -ItemType Directory -Force -Path $ConfigDir > $null
	}
}

$MpvScriptsDir = "$ConfigDir/scripts"
if (!(Test-Path $MpvScriptsDir)) {
	Write-Output "Creating folder: $MpvScriptsDir"
	New-Item -ItemType Directory -Force -Path $MpvScriptsDir > $null
}

Write-Output "→ $ConfigDir"

$BackupDir = "$ConfigDir/.mpvacious-backup"
$ZipFile = "$ConfigDir/mpvacious_tmp.zip"

function DeleteIfExists($Path) {
	if (Test-Path $Path) {
		Remove-Item -LiteralPath $Path -Force -Recurse > $null
	}
}

Function Abort($Message) {
	Write-Output "Error: $Message"
	Write-Output "Aborting!"

	DeleteIfExists($ZipFile)

	Write-Output "Deleting potentially broken install..."
	foreach ($File in $Files) {
		DeleteIfExists("$ConfigDir/$File")
	}

	Write-Output "Restoring backup..."
	foreach ($File in $Files) {
		$FromPath = "$BackupDir/$File"
		if (Test-Path $FromPath) {
			$ToPath = "$ConfigDir/$File"
			$ToDir = Split-Path $ToPath -parent
			New-Item -ItemType Directory -Force -Path $ToDir > $null
			Move-Item -LiteralPath $FromPath -Destination $ToPath -Force > $null
		}
	}

	Write-Output "Deleting backup..."
	DeleteIfExists($BackupDir)

	Exit 1
}

# Ensure install directory exists
if (!(Test-Path -Path $ConfigDir -PathType Container)) {
	if (Test-Path -Path $ConfigDir -PathType Leaf) {
		Abort("Config directory is a file.")
	}
	try {
		New-Item -ItemType Directory -Force -Path $ConfigDir > $null
	}
	catch {
		Abort("Couldn't create config directory.")
	}
}

Write-Output "Backing up..."
foreach ($File in $Files) {
	$FromPath = "$ConfigDir/$File"
	if (Test-Path $FromPath) {
		$ToPath = "$BackupDir/$File"
		$ToDir = Split-Path $ToPath -parent
		try {
			New-Item -ItemType Directory -Force -Path $ToDir > $null
		}
		catch {
			Abort("Couldn't create backup folder: $ToDir")
		}
		try {
			Move-Item -LiteralPath $FromPath -Destination $ToPath -Force > $null
		}
		catch {
			Abort("Couldn't move '$FromPath' to '$ToPath'.")
		}
	}
}

# Install new version
Write-Output "Downloading archive..."
try {
	Invoke-WebRequest -OutFile $ZipFile -Uri $ZipURL > $null
}
catch {
	Abort("Couldn't download: $ZipURL")
}
Write-Output "Extracting archive..."
try {
	Expand-Archive $ZipFile -DestinationPath $MpvScriptsDir -Force > $null
}
catch {
	Abort("Couldn't extract: $ZipFile")
}
Write-Output "Deleting archive..."
DeleteIfExists($ZipFile)
Write-Output "Deleting backup..."
DeleteIfExists($BackupDir)

# Download default config if one doesn't exist yet
try {
	$ScriptOptsDir = "$ConfigDir/script-opts"
	$ConfFile = "$ScriptOptsDir/subs2srs.conf"
	if (!(Test-Path $ConfFile)) {
		Write-Output "Config not found, downloading default subs2srs.conf..."
		New-Item -ItemType Directory -Force -Path $ScriptOptsDir > $null
		Invoke-WebRequest -OutFile $ConfFile -Uri $ConfURL > $null
	}
}
catch {
	Abort("Couldn't download the config file, but mpvacious should be installed correctly.")
}

Write-Output "mpvacious has been installed."
