# ./Config/AdminTweaks.ps1

# ---[ Admin Check & Relaunch Elevated if Needed ]---
function Test-IsAdmin {
    $currentUser  = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser .IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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

# ---[ Script Finished ]---
Write-Host "Admin tweaks completed. Please close this window, and Check logs in $LogPath for details."
Stop-Transcript
