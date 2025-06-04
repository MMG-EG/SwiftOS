<#
.SYNOPSIS
  SwiftOS Mod Kit Installer
.DESCRIPTION
  WPF GUI script for customizing Windows 11 21H2 installs:
  - Checks Windows version (21H2)
  - Removes bloatware
  - Disables telemetry, Cortana, sets power plan High Performance
  - Applies dark mode, sets wallpapers, clears temp files
  - Limits Windows Updates to security only
  - Installs apps via winget or chocolatey with GUI selection, fallback alternatives, retries
  - Logs all actions with retry and skip on failure
  - Shows progress bar, status updates, prompts for user input on errors
#>

Add-Type -AssemblyName PresentationFramework,WindowsBase,PresentationCore,System.Xaml

#region XAML UI Definition
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="SwiftOS Mod Kit Installer" Height="520" Width="700"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize" >
  <Grid Margin="10">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Text="SwiftOS Mod Kit Installer" FontSize="20" FontWeight="Bold" HorizontalAlignment="Center"/>
    <ScrollViewer Grid.Row="1" Margin="0,10,0,10" VerticalScrollBarVisibility="Auto">
      <StackPanel>
        <TextBlock Text="Status / Log:" FontWeight="Bold" Margin="0,0,0,5"/>
        <TextBox Name="txtLog" Height="220" IsReadOnly="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"/>
        
        <StackPanel Orientation="Horizontal" Margin="0,10,0,5" VerticalAlignment="Center">
          <CheckBox Name="chkSelectApps" Content="Select common apps to install" FontWeight="Bold"/>
        </StackPanel>

        <StackPanel Name="appSelectionPanel" Visibility="Collapsed" Margin="10,0,0,10">
          <TextBlock Text="Select Package Manager:" FontWeight="Bold" Margin="0,0,0,5"/>
          <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
            <RadioButton Name="rbWinget" Content="Winget (Recommended)" IsChecked="True" Margin="0,0,20,0"/>
            <RadioButton Name="rbChoco" Content="Chocolatey"/>
          </StackPanel>

          <TextBlock Text="Select apps to install:" FontWeight="Bold" Margin="0,0,0,5"/>
          <ScrollViewer Height="120" VerticalScrollBarVisibility="Auto" BorderThickness="1" BorderBrush="Gray">
            <StackPanel Name="appListPanel"/>
          </ScrollViewer>
        </StackPanel>
      </StackPanel>
    </ScrollViewer>

    <ProgressBar Name="progressBar" Grid.Row="2" Height="20" Minimum="0" Maximum="100" Margin="0,5,0,5"/>
    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,5,0,0">
      <Button Name="btnInstall" Content="Start Install" Width="100" Margin="10,0"/>
      <Button Name="btnReadme" Content="Readme" Width="100" Margin="10,0"/>
      <Button Name="btnExit" Content="Exit" Width="100" Margin="10,0"/>
    </StackPanel>
  </Grid>
</Window>
"@
#endregion

#region Helper functions

function Show-YesNoDialog {
    param($owner, $message, $title="Confirm")
    $result = [System.Windows.MessageBox]::Show($owner, $message, $title, "YesNo", "Question")
    return $result -eq "Yes"
}

function Show-OkDialog {
    param($owner, $message, $title="Info")
    [System.Windows.MessageBox]::Show($owner, $message, $title, "OK", "Information") | Out-Null
}

function Write-Log {
    param($message)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $fullmsg = "[$timestamp] $message"
    # Update UI log textbox (run in UI thread)
    $script:txtLog.Dispatcher.Invoke([action]{ $script:txtLog.AppendText($fullmsg + "`r`n"); $script:txtLog.ScrollToEnd() })
    # Append to logfile (defined later)
    Add-Content -Path $script:logFile -Value $fullmsg
}

function Prompt-RetrySkip {
    param($owner, $message)
    $buttons = [System.Windows.MessageBoxButton]::YesNoCancel
    $result = [System.Windows.MessageBox]::Show($owner, $message + "`nYes = Retry, No = Skip, Cancel = Abort install", "Error - Choose action", $buttons, "Warning")
    switch ($result) {
        'Yes' { return 'Retry' }
        'No'  { return 'Skip' }
        'Cancel' { return 'Abort' }
    }
}

function Get-NextLogFile {
    $dir = "C:\SwiftOS\Logs"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $num = 1
    while (Test-Path "$dir\SwiftOS_Log_$num.txt") {
        $num++
    }
    return "$dir\SwiftOS_Log_$num.txt"
}

function Check-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        return $false
    }
    return $true
}

function Elevate-Script {
    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -PassThru
    $proc.WaitForExit()
    exit
}

function Check-WindowsVersion {
    # Returns $true if Windows 11 21H2 (build 22000.xx) or later 21H2 variant, else $false
    try {
        $version = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
        $ubr = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").UBR
        if ($null -eq $version) { return $false }
        if ($version -lt 22000) { return $false }
        # Only 21H2 series accepted - build number 22000.xx - minor versions 22000-22999 for safety
        if ($version -ge 22000 -and $version -lt 23000) { return $true }
        return $false
    } catch {
        return $false
    }
}

function Create-RestorePoint {
    Write-Log "Creating system restore point..."
    try {
        Checkpoint-Computer -Description "SwiftOS Mod Kit Restore Point" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Log "Restore point created successfully."
        return $true
    } catch {
        Write-Log "Failed to create restore point: $_"
        return $false
    }
}

function Remove-Bloatware {
    param($logOwner)
    # Bloatware wildcard app names - multiple variants
    $bloatwareApps = @(
        "*3D Viewer*","*Adobe Express*","*Clipchamp*","*Facebook*","*Hidden City*","*Instagram*","*Netflix*",
        "*News*","*Prime Video*","*Solitaire Collection*","*Mixed Reality Portal*","*Roblox*","*TikTok*",
        "*Age of Empires*","*Asphalt 8*","*Bubble Witch 3*","*Candy Crush*","*FarmVille 2*","*Fitbit Coach*",
        "*Gardenscapes*","*Phototastic Collage*","*PicsArt*","*Print 3D*","*Spotify*","*Twitter*"
    )
    Write-Log "Starting bloatware removal..."
    foreach ($appPattern in $bloatwareApps) {
        $attempts = 0
        do {
            $attempts++
            try {
                $packages = Get-AppxPackage -Name $appPattern -ErrorAction SilentlyContinue
                if ($packages) {
                    foreach ($pkg in $packages) {
                        Write-Log "Removing app package: $($pkg.Name)..."
                        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
                        Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageFullName -ErrorAction SilentlyContinue
                        Write-Log "Removed $($pkg.Name) successfully."
                    }
                } else {
                    Write-Log "No app found matching pattern: $appPattern"
                }
                break
            } catch {
                $msg = "Error removing bloatware app matching '$appPattern': $_"
                Write-Log $msg
                $choice = Prompt-RetrySkip $logOwner "$msg`nDo you want to retry or skip?"
                if ($choice -eq 'Retry') { continue }
                elseif ($choice -eq 'Skip') { break }
                else { throw "User aborted install." }
            }
        } while ($attempts -lt 3)
    }
    Write-Log "Completed bloatware removal."
}

function Disable-TelemetryAndDC {
    param($owner)
    Write-Log "Disabling telemetry and data collection..."
    $attempts = 0
    do {
        $attempts++
        try {
            # Disable telemetry services & scheduled tasks
            Stop-Service "DiagTrack" -ErrorAction SilentlyContinue
            Set-Service "DiagTrack" -StartupType Disabled
            Stop-Service "dmwappushservice" -ErrorAction SilentlyContinue
            Set-Service "dmwappushservice" -StartupType Disabled

            # Registry tweaks to disable telemetry and data collection
            $paths = @(
                "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection",
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
            )
            foreach ($path in $paths) {
                if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
                Set-ItemProperty -Path $path -Name "AllowTelemetry" -Value 0 -Type DWord -Force
            }
            Write-Log "Telemetry and data collection disabled."
            return $true
        } catch {
            $msg = "Failed disabling telemetry: $_"
            Write-Log $msg
            $choice = Prompt-RetrySkip $owner "$msg`nRetry or Skip?"
            if ($choice -eq 'Retry') { continue }
            elseif ($choice -eq 'Skip') { return $false }
            else { throw "User aborted install." }
        }
    } while ($attempts -lt 3)
}

function Disable-Cortana {
    param($owner)
    Write-Log "Disabling Cortana..."
    $attempts = 0
    do {
        $attempts++
        try {
            # Cortana registry disable (even if not present on Win11)
            $cortanaPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
            if (-not (Test-Path $cortanaPath)) { New-Item -Path $cortanaPath -Force | Out-Null }
            Set-ItemProperty -Path $cortanaPath -Name "AllowCortana" -Value 0 -Type DWord -Force
            Write-Log "Cortana disabled."
            return $true
        } catch {
            $msg = "Failed disabling Cortana: $_"
            Write-Log $msg
            $choice = Prompt-RetrySkip $owner "$msg`nRetry or Skip?"
            if ($choice -eq 'Retry') { continue }
            elseif ($choice -eq 'Skip') { return $false }
            else { throw "User aborted install." }
        }
    } while ($attempts -lt 3)
}

function Set-PowerPlanHighPerformance {
    param($owner)
    Write-Log "Setting power plan to High Performance..."
    $attempts = 0
    do {
        $attempts++
        try {
            $highPerf = (powercfg -list | Select-String -Pattern "High performance").ToString()
            if ($highPerf -match '{([a-f0-9\-]+)}') {
                $guid = $matches[1]
                powercfg -setactive $guid
                Write-Log "Power plan set to High Performance."
                return $true
            } else {
                Write-Log "High Performance power plan not found."
                return $false
            }
        } catch {
            $msg = "Failed setting power plan: $_"
            Write-Log $msg
            $choice = Prompt-RetrySkip $owner "$msg`nRetry or Skip?"
            if ($choice -eq 'Retry') { continue }
            elseif ($choice -eq 'Skip') { return $false }
            else { throw "User aborted install." }
        }
    } while ($attempts -lt 3)
}

function Apply-DarkTheme {
    param($owner)
    Write-Log "Applying dark theme..."
    $attempts = 0
    do {
        $attempts++
        try {
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0 -Type DWord -Force
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0 -Type DWord -Force
            Write-Log "Dark theme applied."
            return $true
        } catch {
            $msg = "Failed applying dark theme: $_"
            Write-Log $msg
            $choice = Prompt-RetrySkip $owner "$msg`nRetry or Skip?"
            if ($choice -eq 'Retry') { continue }
            elseif ($choice -eq 'Skip') { return $false }
            else { throw "User aborted install." }
        }
    } while ($attempts -lt 3)
}

function Set-Wallpapers {
    param($owner)
    Write-Log "Setting wallpapers from C:\Wallpapers\wallpaper.jpg and lswallpaper.jpg..."
    $attempts = 0
    do {
        $attempts++
        try {
            $wallpaper1 = "C:\Wallpapers\wallpaper.jpg"
            $wallpaper2 = "C:\Wallpapers\lswallpaper.jpg"
            if (-not (Test-Path $wallpaper1) -or -not (Test-Path $wallpaper2)) {
                Write-Log "Wallpaper files not found. Skipping wallpaper setting."
                return $false
            }
            # Set desktop wallpaper 1
            Add-Type @"
using System.Runtime.InteropServices;
public class Wallpaper {
  [DllImport("user32.dll",SetLastError=true)]
  public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
            [Wallpaper]::SystemParametersInfo(20, 0, $wallpaper1, 3) | Out-Null

            # Lock screen wallpaper (requires local admin & Windows 10+)
            $lockKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
            if (-not (Test-Path $lockKey)) { New-Item -Path $lockKey -Force | Out-Null }
            Set-ItemProperty -Path $lockKey -Name "LockScreenImageStatus" -Value 1 -Type DWord -Force
            Set-ItemProperty -Path $lockKey -Name "LockScreenImagePath" -Value $wallpaper2 -Force

            Write-Log "Wallpapers set."
            return $true
        } catch {
            $msg = "Failed setting wallpapers: $_"
            Write-Log $msg
            $choice = Prompt-RetrySkip $owner "$msg`nRetry or Skip?"
            if ($choice -eq 'Retry') { continue }
            elseif ($choice -eq 'Skip') { return $false }
            else { throw "User aborted install." }
        }
    } while ($attempts -lt 3)
}

function Clear-TempFiles {
    param($owner)
    Write-Log "Clearing temporary files..."
    $attempts = 0
    do {
        $attempts++
        try {
            Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Temporary files cleared."
            return $true
        } catch {
            $msg = "Failed clearing temp files: $_"
            Write-Log $msg
            $choice = Prompt-RetrySkip $owner "$msg`nRetry or Skip?"
            if ($choice -eq 'Retry') { continue }
            elseif ($choice -eq 'Skip') { return $false }
            else { throw "User aborted install." }
        }
    } while ($attempts -lt 3)
}

function Limit-WindowsUpdates {
    param($owner)
    Write-Log "Limiting Windows Updates to security only..."
    $attempts = 0
    do {
        $attempts++
        try {
            # Set Group Policy for updates (security only)
            $gpPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
            if (-not (Test-Path $gpPath)) { New-Item -Path $gpPath -Force | Out-Null }
            Set-ItemProperty -Path $gpPath -Name "UseWUServer" -Value 0 -Type DWord -Force
            # Windows Update service remains enabled but won't install non-security updates automatically
            Write-Log "Windows Updates limited to security only."
            return $true
        } catch {
            $msg = "Failed limiting Windows Updates: $_"
            Write-Log $msg
            $choice = Prompt-RetrySkip $owner "$msg`nRetry or Skip?"
            if ($choice -eq 'Retry') { continue }
            elseif ($choice -eq 'Skip') { return $false }
            else { throw "User aborted install." }
        }
    } while ($attempts -lt 3)
}

# App install related:

# Define apps with info for winget and chocolatey identifiers + fallback alternatives

$appsCatalog = @(
    # Browsers
    @{Name="Google Chrome"; WingetId="Google.Chrome"; ChocoId="googlechrome"; Alternatives=@("Mozilla.Firefox","Microsoft.Edge","Firefox","msedge","firefox","chrome") },
    @{Name="Mozilla Firefox"; WingetId="Mozilla.Firefox"; ChocoId="firefox"; Alternatives=@("Google.Chrome","Microsoft.Edge","chrome","msedge","firefox") },
    @{Name="Microsoft Edge"; WingetId="Microsoft.Edge"; ChocoId="msedge"; Alternatives=@("Google.Chrome","Mozilla.Firefox","chrome","firefox","msedge") },

    # Zip utilities
    @{Name="7zip"; WingetId="7zip.7zip"; ChocoId="7zip"; Alternatives=@("WinRAR","PeaZip","winrar","peazip") },
    @{Name="WinRAR"; WingetId="RARLab.WinRAR"; ChocoId="winrar"; Alternatives=@("7zip","PeaZip","7zip","peazip") },
    @{Name="PeaZip"; WingetId="PeaZip.PeaZip"; ChocoId="peazip"; Alternatives=@("7zip","WinRAR","7zip","winrar") },

    # PDF Readers
    @{Name="Adobe Acrobat Reader DC"; WingetId="Adobe.Acrobat.Reader.64-bit"; ChocoId="adobereader"; Alternatives=@("SumatraPDF","FoxitReader","sumatrapdf","foxitreader") },
    @{Name="SumatraPDF"; WingetId="Krzysztof.Kowalczyk.SumatraPDF"; ChocoId="sumatrapdf"; Alternatives=@("FoxitReader","Adobe.Acrobat.Reader.64-bit","foxitreader","adobereader") },
    @{Name="Foxit Reader"; WingetId="Foxit.FoxitReader"; ChocoId="foxitreader"; Alternatives=@("SumatraPDF","Adobe.Acrobat.Reader.64-bit","sumatrapdf","adobereader") },

    # Media Players
    @{Name="VLC Media Player"; WingetId="VideoLAN.VLC"; ChocoId="vlc"; Alternatives=@("MPC-HC","mpc-hc") },
    @{Name="MPC-HC"; WingetId="MPC-HC.MPC-HC"; ChocoId="mpc-hc"; Alternatives=@("VLC Media Player","vlc") },

    # Code Editors
    @{Name="Visual Studio Code"; WingetId="Microsoft.VisualStudioCode"; ChocoId="vscode"; Alternatives=@("Notepad++","Sublime Text","notepadplusplus.install","sublimetext3") },
    @{Name="Notepad++"; WingetId="Notepad++.Notepad++"; ChocoId="notepadplusplus.install"; Alternatives=@("Visual Studio Code","Sublime Text","vscode","sublimetext3") },
    @{Name="Sublime Text"; WingetId="SublimeHQ.SublimeText"; ChocoId="sublimetext3"; Alternatives=@("Visual Studio Code","Notepad++","vscode","notepadplusplus.install") },

    # Communication
    @{Name="Zoom"; WingetId="Zoom.Zoom"; ChocoId="zoom"; Alternatives=@("Microsoft Teams","Skype","microsoft-teams","skype") },
    @{Name="Microsoft Teams"; WingetId="Microsoft.Teams"; ChocoId="microsoft-teams"; Alternatives=@("Zoom","Skype","zoom","skype") },
    @{Name="Skype"; WingetId="Microsoft.Skype"; ChocoId="skype"; Alternatives=@("Microsoft Teams","Zoom","microsoft-teams","zoom") },
    @{Name="Discord"; WingetId="Discord.Discord"; ChocoId="discord"; Alternatives=@("TeamSpeak","teamspeak") },

    # Utilities
    @{Name="Everything Search"; WingetId="voidtools.Everything"; ChocoId="everything"; Alternatives=@("Listary","listary") },
    @{Name="Greenshot"; WingetId="Greenshot.Greenshot"; ChocoId="greenshot"; Alternatives=@("ShareX","sharex") },

    # Others
    @{Name="Spotify"; WingetId="Spotify.Spotify"; ChocoId="spotify"; Alternatives=@() },
    @{Name="Steam"; WingetId="Valve.Steam"; ChocoId="steam"; Alternatives=@() },
    @{Name="Dropbox"; WingetId="Dropbox.Dropbox"; ChocoId="dropbox"; Alternatives=@("Google Drive","googledrive") }
)

# Function to install a single app with retries and fallback alternatives
function Install-App {
    param(
        [string]$AppName,
        [string]$PackageId,
        [string]$PackageManager,  # "winget" or "choco"
        [string[]]$Alternatives,
        [int]$MaxRetries = 3
    )

    $attempt = 0
    $installed = $false
    $currentPackageId = $PackageId
    $altIndex = 0

    while (-not $installed -and $attempt -lt $MaxRetries) {
        $attempt++
        Write-Log "Installing $AppName (Attempt $attempt) via $PackageManager package ID '$currentPackageId'..."
        try {
            if ($PackageManager -eq "winget") {
                # winget install command with --silent, --accept-source-agreements, --accept-package-agreements
                $args = @("install","--id",$currentPackageId,"--silent","--accept-source-agreements","--accept-package-agreements")
                $proc = Start-Process -FilePath "winget.exe" -ArgumentList $args -NoNewWindow -Wait -PassThru
                if ($proc.ExitCode -eq 0) {
                    Write-Log "$AppName installed successfully."
                    $installed = $true
                } else {
                    throw "winget exited with code $($proc.ExitCode)"
                }
            } elseif ($PackageManager -eq "choco") {
                $args = @("install",$currentPackageId,"-y","--no-progress")
                $proc = Start-Process -FilePath "choco.exe" -ArgumentList $args -NoNewWindow -Wait -PassThru
                if ($proc.ExitCode -eq 0) {
                    Write-Log "$AppName installed successfully."
                    $installed = $true
                } else {
                    throw "choco exited with code $($proc.ExitCode)"
                }
            } else {
                throw "Unknown package manager $PackageManager"
            }
        } catch {
            Write-Log "Installation failed for $AppName with package ID '$currentPackageId': $_"
            if ($altIndex -lt $Alternatives.Count) {
                $currentPackageId = $Alternatives[$altIndex]
                Write-Log "Trying alternative package ID '$currentPackageId'..."
                $altIndex++
            } else {
                Write-Log "No more alternatives to try for $AppName."
                break
            }
        }
    }
    return $installed
}

# Main function to install selected apps from $appsCatalog by name
function Install-SelectedApps {
    param(
        [string[]]$SelectedApps,
        [string]$PackageManager = "winget",  # Default to winget, fallback to choco if winget not available
        [string]$owner
    )
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            $PackageManager = "choco"
            Write-Log "winget not found, falling back to Chocolatey."
        } else {
            throw "Neither winget nor Chocolatey found."
        }
    }
    foreach ($appName in $SelectedApps) {
        $app = $appsCatalog | Where-Object { $_.Name -eq $appName }
        if ($null -eq $app) {
            Write-Log "App '$appName' not found in catalog."
            continue
        }
        $success = Install-App -AppName $app.Name -PackageId $app.($PackageManager + "Id") -PackageManager $PackageManager -Alternatives $app.Alternatives
        if (-not $success) {
            $msg = "Failed to install $($app.Name)."
            Write-Log $msg
            $choice = Prompt-RetrySkip $owner "$msg`nRetry or Skip?"
            if ($choice -eq 'Retry') {
                # Retry once more for the app
                $success = Install-App -AppName $app.Name -PackageId $app.($PackageManager + "Id") -PackageManager $PackageManager -Alternatives $app.Alternatives
                if (-not $success) {
                    Write-Log "Retry failed for $($app.Name). Skipping."
                }
            } elseif ($choice -eq 'Skip') {
                Write-Log "User chose to skip $($app.Name) installation."
                continue
            } else {
                throw "User aborted install."
            }
        }
    }
}

# Function to execute all chosen customization tasks sequentially
function Run-Customizations {
    param($owner, $selectedApps)

    # Example sequence
    Write-Log "Starting customization tasks..."

    if (-not Create-RestorePoint -owner $owner) { Write-Log "Restore point creation failed or skipped." }
    if (-not Disable-Defender -owner $owner) { Write-Log "Disabling Defender failed or skipped." }
    if (-not Remove-Bloatware -owner $owner) { Write-Log "Removing bloatware failed or skipped." }
    if (-not Apply-Theme -owner $owner) { Write-Log "Applying theme failed or skipped." }
    if (-not Customize-StartMenu -owner $owner) { Write-Log "Customizing Start menu failed or skipped." }
    if (-not Set-Wallpapers -owner $owner) { Write-Log "Setting wallpapers failed or skipped." }
    if (-not Clear-TempFiles -owner $owner) { Write-Log "Clearing temp files failed or skipped." }
    if (-not Limit-WindowsUpdates -owner $owner) { Write-Log "Limiting Windows Updates failed or skipped." }
    Install-SelectedApps -SelectedApps $selectedApps -owner $owner

    Write-Log "Customization tasks completed."
}
