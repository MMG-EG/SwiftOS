# ./LaunchTweaks.ps1

# Function to check if running as admin
function Test-IsAdmin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Prevent running launcher itself as admin
if (Test-IsAdmin) {
    Write-Warning "Do NOT run this launcher as Administrator. Please run it as a regular user."
    exit
}

# Welcome message and pause
Write-Host "Welcome to SwiftOS Setup!"
Start-Sleep -Seconds 2

# Define full paths to the scripts in the Config folder
$userScript = Join-Path -Path $PSScriptRoot -ChildPath "Config\UserTweaks.ps1"
$adminScript = Join-Path -Path $PSScriptRoot -ChildPath "Config\AdminTweaks.ps1"

# Execute the user-level tweaks script synchronously
Write-Host "Executing user-level tweaks... After it finishes, please close the script."
& $userScript

# Launch the admin-level tweaks script elevated and wait for completion
Write-Host "Launching admin-level tweaks with elevation... After it finishes, please close the script."
$process = Start-Process -FilePath "powershell.exe" `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$adminScript`"" `
    -Verb RunAs -PassThru

$process.WaitForExit()

Write-Host "All tweaks completed successfully."

# Ask if user wants to reboot now
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

if (Ask-YesNo "It is recommended to reboot your device now. Do you want to reboot now?") {
    Write-Host "Rebooting system..."
    Restart-Computer -Force
} else {
    Write-Host "Please remember to reboot your device later for changes to take effect."
}