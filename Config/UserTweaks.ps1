# ./Config/UserTweaks.ps1

# ---[ Setup Logs & Config Paths ]---
$LogPath = ".\Logs"
$ConfigPath = ".\Config"
New-Item -ItemType Directory -Force -Path $LogPath, $ConfigPath | Out-Null
Start-Transcript -Path "$LogPath\SwiftOS-Log.txt" -Append

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

# ---[ Set Swift OS Branded Wallpapers ]---
function Set-SwiftOSWallpapers {
    $rootConfig = Join-Path $PSScriptRoot "..\Config"
    $desktopWallpaper = Join-Path $rootConfig "wallpaper.jpg"
    $lockScreenWallpaper = Join-Path $rootConfig "lswallpaper.jpg"

    if (-not (Test-Path $desktopWallpaper)) {
        Write-Warning "Desktop wallpaper image not found at $desktopWallpaper"
        return
    }
    if (-not (Test-Path $lockScreenWallpaper)) {
        Write-Warning "Lock screen wallpaper image not found at $lockScreenWallpaper"
        return
    }

    Try {
        # Set desktop wallpaper
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "Wallpaper" -Value $desktopWallpaper
        rundll32.exe user32.dll,UpdatePerUserSystemParameters

        # Set lock screen wallpaper (requires admin privileges, but we'll attempt for current user)
        $personalizationPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
        if (-not (Test-Path $personalizationPath)) {
            New-Item -Path $personalizationPath -Force | Out-Null
        }
        Set-ItemProperty -Path $personalizationPath -Name "LockScreenImagePath" -Value $lockScreenWallpaper -Force

        # Windows lock screen can also be set via the registry key at:
        # HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization
        # but that requires admin rights; here prompt user if they want to elevate

        Write-Host "Swift OS desktop and lock screen wallpapers have been set."
    } catch {
        Write-Warning "Failed to set wallpapers: $_"
    }
}

# --- Ask User to Set Swift OS Branded Wallpapers ---
if (Ask-YesNo "Would you like to set Swift OS branded lock screen and desktop wallpaper?") {
    Set-SwiftOSWallpapers
} else {
    Write-Host "Skipped setting Swift OS branded wallpapers."
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
        $personalizeKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        $userPrefsKey = "HKCU:\Control Panel\Desktop"

        # Disable window animations
        Set-ItemProperty -Path $userPrefsKey -Name "User PreferencesMask" -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -Force

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

        Write-Host "Look tweaks applied for better performance on low-end devices."
    } else {
        Write-Host "Skipped look tweaks for low-end devices."
    }
}

# --- Run Selections ---
Set-FileVisibilityOptions
Set-BingSearch
Set-TaskbarTransparency
Set-LowEndLookTweaks

# ---[ Script Finished ]---
Write-Host "User tweaks completed. Check logs in $LogPath for details."
Stop-Transcript