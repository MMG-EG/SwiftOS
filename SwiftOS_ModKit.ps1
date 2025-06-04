# Root Folder: Script.ps1
# Config Folder: ./Config/

# ---[ Admin Check & Relaunch Elevated if Needed ]---
function Test-IsAdmin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    Write-Host "Elevating script with administrator privileges..."
    Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile -NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs
    exit
}

# ---[ Setup Logs & Config Paths ]---
$LogPath = ".\Logs"
$ConfigPath = ".\Config"
New-Item -ItemType Directory -Force -Path $LogPath, $ConfigPath | Out-Null
Start-Transcript -Path "$LogPath\SwiftOS-Log.txt" -Append

# ---[ Windows Build Check ]---
try {
    $currentBuild = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
    if (-not $currentBuild) {
        throw "Failed to detect Windows build number."
    }
    $currentBuild = [int]$currentBuild
    $minSupportedBuild = 22000
    if ($currentBuild -lt $minSupportedBuild) {
        Write-Error "Unsupported Windows build: $currentBuild. Minimum required is $minSupportedBuild."
        exit
    }
    Write-Host "Windows build $currentBuild detected, compatible."
} catch {
    Write-Error "Error detecting Windows build: $_"
    exit
}

# ---[ Restore Point Management ]---
function Is-SystemProtectionEnabled {
    $sysDrive = (Get-WmiObject -Class Win32_OperatingSystem).SystemDrive
    $sp = Get-CimInstance -Namespace root/default -ClassName SystemRestore | Where-Object { $_.DriveLetter -eq $sysDrive }
    return $sp -and $sp.Enabled
}
function Create-RestorePoint {
    if (-not (Is-SystemProtectionEnabled)) {
        Write-Warning "System Protection is disabled on $((Get-WmiObject -Class Win32_OperatingSystem).SystemDrive). Restore point creation skipped."
        return
    }
    try {
        Write-Host "Creating system restore point..."
        Checkpoint-Computer -Description "SwiftOS Mod Kit Restore Point" -RestorePointType "MODIFY_SETTINGS"
        Write-Host "Restore point created successfully."
    } catch {
        Write-Warning "Restore point creation failed: $_"
    }
}

if ((Read-Host "Create system restore point before changes? [Y/N]").ToUpper() -eq 'Y') {
    Create-RestorePoint
}

# ---[ Utility: Prompt Yes/No ]---
function Ask-YesNo($message) {
    while ($true) {
        $response = Read-Host "$message [Y/N]"
        switch ($response.ToUpper()) {
            'Y' { return $true }
            'N' { return $false }
            default { Write-Host "Please enter Y or N." }
        }
    }
}

# ---[ Bloatware Removal ]---
$keepApps = @(
    "Microsoft.WindowsStore",
    "Microsoft.MicrosoftEdge.Stable",
    "Microsoft.WindowsNotepad",
    "Microsoft.ScreenSketch",
    "Microsoft.Windows.Photos",
    "Microsoft.WindowsCalculator",
    "Microsoft.Windows.Settings",
    "Microsoft.Windows.SecHealthUI",
    "Microsoft.DesktopAppInstaller",
    "Microsoft.StorePurchaseApp"
)

if (Ask-YesNo "Aggressively remove all system apps except essential ones? This keeps Store, Edge, Notepad, Snip & Sketch, Photos, Calculator, Settings, Defender.") {
    $allPackages = Get-AppxPackage -AllUsers
    foreach ($pkg in $allPackages) {
        if ($keepApps -notcontains $pkg.Name) {
            try {
                Write-Host "Removing bloatware app: $($pkg.Name)"
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                Write-Host "Removed $($pkg.Name) successfully."
            } catch {
                Write-Warning "Failed to remove $($pkg.Name): $_"
            }
        } else {
            Write-Host "Keeping app: $($pkg.Name)"
        }
    }
}

function Remove-ProvisionedPackages {
    Write-Host "Removing provisioned app packages (pre-installed apps for new users)..."
    $provisioned = Get-AppxProvisionedPackage -Online | Where-Object {
        $keepApps -notcontains $_.DisplayName
    }
    foreach ($pkg in $provisioned) {
        try {
            Write-Host "Removing provisioned package: $($pkg.DisplayName)"
            Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageName -ErrorAction Stop
            Write-Host "Provisioned package removed: $($pkg.DisplayName)"
        } catch {
            Write-Warning "Failed to remove provisioned package $($pkg.DisplayName): $_"
        }
    }
}

if (Ask-YesNo "Remove provisioned packages to prevent reinstallation on new user profiles?") {
    Remove-ProvisionedPackages
}

function Clean-AppRemnants {
    Write-Host "Cleaning leftover app data and cache folders..."
    $paths = @(
        "$env:LOCALAPPDATA\Packages\*",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache\*",
        "$env:LOCALAPPDATA\Microsoft\Windows\WebCache\*",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\*.lnk"
    )
    foreach ($path in $paths) {
        try {
            Write-Host "Cleaning $path"
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Warning "Failed to clean ${path}: $_"
        }
    }
}

if (Ask-YesNo "Clean leftover app data and cache folders?") {
    Clean-AppRemnants
}

# --- Show File Extensions & Hidden Files Prompt ---
function Set-FileVisibilityOptions {
    $response = Read-Host "`nShow file extensions and hidden files? (yes/no)"
    if ($response -match '^(y|yes)$') {
        $explorerKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Set-ItemProperty -Path $explorerKey -Name "HideFileExt" -Value 0
        Set-ItemProperty -Path $explorerKey -Name "Hidden" -Value 1
        Set-ItemProperty -Path $explorerKey -Name "ShowSuperHidden" -Value 1
        Write-Host "File extensions and hidden items will be shown."
    } else {
        Write-Host "Skipped showing file extensions and hidden files."
    }
}

# --- Disable Bing Search Prompt ---
function Set-BingSearch {
    $response = Read-Host "`nDisable Bing in Start Menu Search? (yes/no)"
    if ($response -match '^(y|yes)$') {
        $searchKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
        if (-not (Test-Path $searchKey)) {
            New-Item -Path $searchKey -Force | Out-Null
        }
        Set-ItemProperty -Path $searchKey -Name "BingSearchEnabled" -Value 0 -Force
        Set-ItemProperty -Path $searchKey -Name "CortanaConsent" -Value 0 -Force
        Write-Host "Bing Search disabled in Start Menu."
    } else {
        Write-Host "Skipped disabling Bing Search."
    }
}

# --- Disable Taskbar Transparency Prompt ---
function Set-TaskbarTransparency {
    $response = Read-Host "`nDisable taskbar transparency? (yes/no)"
    if ($response -match '^(y|yes)$') {
        $personalizeKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        Set-ItemProperty -Path $personalizeKey -Name "EnableTransparency" -Value 0 -Force
        Write-Host "Taskbar transparency disabled."
    } else {
        Write-Host "Skipped disabling taskbar transparency."
    }
}

# --- Look Tweaks for Low-End Devices ---
function Set-LowEndLookTweaks {
    $response = Read-Host "`nApply look tweaks for low-end devices (disable animations, effects)? (yes/no)"
    if ($response -match '^(y|yes)$') {
        Write-Host "Applying low-end device visual tweaks..."

        $desktopKey = "HKCU:\Control Panel\Desktop\WindowMetrics"
        $desktopPerformanceKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        $explorerKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        $personalizeKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        $userPrefsKey = "HKCU:\Control Panel\Desktop"

        # Disable window animations
        Set-ItemProperty -Path $userPrefsKey -Name "UserPreferencesMask" -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -Force

        # Disable menu animations, fade effects, tooltip animations, smooth scrolling
        $performanceKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        if (-not (Test-Path $performanceKey)) {
            New-Item -Path $performanceKey -Force | Out-Null
        }
        Set-ItemProperty -Path $performanceKey -Name "VisualFXSetting" -Value 2 -Force  # 2 = Adjust for best performance

        # Disable shadows under windows
        Set-ItemProperty -Path $userPrefsKey -Name "DragFullWindows" -Value 0 -Force

        # Disable transparent glass effects
        Set-ItemProperty -Path $personalizeKey -Name "EnableTransparency" -Value 0 -Force

        # Additional tweaks via system parameters for smoother UI performance
        # Disable tooltips animation and fade effect (registry path)
        $tooltipKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Set-ItemProperty -Path $tooltipKey -Name "ShowInfoTip" -Value 0 -Force

        Write-Host "Look tweaks applied for better performance on low-end devices."
    } else {
        Write-Host "Skipped look tweaks for low-end devices."
    }
}

# --- Run Selections (including the new look tweaks option) ---
Set-FileVisibilityOptions
Set-BingSearch
Set-TaskbarTransparency
Set-LowEndLookTweaks

# ---[ Telemetry Disable ]---
function Disable-Telemetry {
    Write-Host "Disabling Windows Telemetry and Data Collection..."
    $telemetryKeys = @{
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" = @{ "AllowTelemetry" = 0 }
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" = @{ "AllowTelemetry" = 0 }
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" = @{ "DisableCortana" = 1 }
    }
    foreach ($path in $telemetryKeys.Keys) {
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        foreach ($name in $telemetryKeys[$path].Keys) {
            Set-ItemProperty -Path $path -Name $name -Value $telemetryKeys[$path][$name] -Force
        }
    }
    foreach ($svcName in @("DiagTrack","dmwappushservice")) {
        $svc = Get-Service $svcName -ErrorAction SilentlyContinue
        if ($svc) {
            if ($svc.Status -eq 'Running') { Stop-Service $svc.Name -Force }
            Set-Service $svc.Name -StartupType Disabled
        }
    }
    Write-Host "Telemetry and Cortana disabled."
}

if (Ask-YesNo "Disable Windows Telemetry, Cortana, and related data collection?") {
    Disable-Telemetry
}

# ---[ Windows Update Configuration ]---
function Configure-WindowsUpdate {
    Write-Host "Configuring Windows Update settings..."
    $choice = Read-Host "Choose update option:
1) Disable all Windows Updates (NOT recommended)
2) Disable feature updates but keep security updates (Recommended)
Enter 1 or 2"
    switch ($choice) {
        '1' {
            Write-Host "Disabling all Windows Updates..."
            Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
            Set-Service -Name wuauserv -StartupType Disabled
            Get-ScheduledTask -TaskName "Scheduled Start*" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
            New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Value 1 -PropertyType DWORD -Force | Out-Null
            Write-Host "All Windows Updates disabled."
        }
        '2' {
            Write-Host "Disabling feature updates but keeping security updates..."
            $currentVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ReleaseId
            if (-not $currentVersion) { $currentVersion = "2009" }
            $WUPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
            if (-not (Test-Path $WUPath)) { New-Item -Path $WUPath -Force | Out-Null }
            New-ItemProperty -Path $WUPath -Name "DeferFeatureUpdates" -Value 1 -PropertyType DWORD -Force | Out-Null
            New-ItemProperty -Path $WUPath -Name "DeferFeatureUpdatesPeriodInDays" -Value 365 -PropertyType DWORD -Force | Out-Null
            Write-Host "Feature updates deferred for 365 days."
        }
        default {
            Write-Warning "Invalid choice, skipping Windows Update configuration."
        }
    }
}

if (Ask-YesNo "Configure Windows Update settings?") {
    Configure-WindowsUpdate
}

# ---[ Power Plan Setup ]---
function Setup-PowerPlan {
    Write-Host "Configuring power plan to High Performance..."
    $highPerf = (powercfg -list | Select-String -Pattern "High performance")
    if (-not $highPerf) {
        Write-Host "High Performance power plan not found, creating one..."
        powercfg -duplicatescheme SCHEME_MIN
    }
    powercfg -setactive SCHEME_MIN
    Write-Host "High Performance power plan set."
}

if (Ask-YesNo "Set power plan to High Performance?") {
    Setup-PowerPlan
}

# ---[ Script Finished ]---
Write-Host "SwiftOS Mod Kit completed. Check logs in $LogPath for details."
Stop-Transcript