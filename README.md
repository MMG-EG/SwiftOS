<p align="center">
  <strong style="font-size: 2.5em;">SwiftOS Mod Kit</strong>
</p>

---

## Overview

**SwiftOS** is a comprehensive Windows 11 customization and optimization toolkit designed to empower users with fine-grained control over system settings, privacy configurations, and visual customization.  
It enables both standard users and system administrators to apply targeted tweaks efficiently, ensuring optimal performance, enhanced privacy, and a personalized user experience.

---

## Requirements

- **Operating System:** Windows 11 (Version 21H2 or later recommended)  
- **PowerShell:** Version 5.1 or newer (PowerShell 7+ supported but not required)  
- **Execution Policy:** Must allow script execution (`RemoteSigned` or less restrictive)  
- **System Protection:** System Restore must be enabled for creating restore points during admin tweaks  
- **User Privileges:**  
  - User-level tweaks require **standard user** privileges  
  - Admin-level tweaks require **administrative** privileges (UAC prompt)

> **Note:** Ensure your environment meets these criteria for smooth and safe operation.

---

## Features

### User-Level Tweaks
Modify Windows user-specific settings such as:

- Show/hide file extensions and hidden files  
- Disable Bing integration in Start Menu Search  
- Disable taskbar transparency  
- Apply visual tweaks optimized for low-end hardware  
- Set branded desktop and lock screen wallpapers

### Admin-Level Tweaks
Require elevation to modify system-wide settings including:

- Windows Update configuration  
- Removal of bloatware apps and provisioned packages  
- Creation of system restore points  
- Disabling Windows telemetry and Cortana  
- Setting high-performance power plans

### Additional Highlights

- **Safe Elevation Management:**  
  User and admin tweaks are separated to ensure changes to `HKCU` run under the correct user context and admin tweaks run elevated to modify machine settings.

- **Logging and Error Handling:**  
  Activities are logged using PowerShell transcripts for auditability and troubleshooting.

- **Wallpaper Configuration:**  
  User wallpapers and lock screen images are stored in the `Config` folder and applied by user-level scripts to preserve personalization independently of admin tweaks.

---

## Architecture and Implementation Details

### Script Structure

SwiftOS_Mod_Kit/
├── LaunchTweaks.ps1 # Main launcher script
├── Config/
│ ├── UserTweaks.ps1 # User-level tweaks (runs without elevation)
│ └── AdminTweaks.ps1 # Admin-level tweaks (runs elevated)
│ └── wallpaper.jpg # Desktop wallpaper image
│ └── lswallpaper.jpg # Lock screen wallpaper image

yaml
Copy
Edit

- `LaunchTweaks.ps1` runs `UserTweaks.ps1` first, then elevates and runs `AdminTweaks.ps1`.
- Separation ensures user registry (`HKCU`) tweaks run correctly without elevation.
- Admin tweaks modify system-wide settings, requiring UAC elevation.

---

## Usage

1. Clone or download the repository to your Windows 11 machine:

git clone https://github.com/MMG-EG/SwiftOS.git

2. Open PowerShell as a standard user (do not run as administrator).

3. Navigate to the script directory and run the launcher:

cd path\to\SwiftOS_Mod_Kit
.\SwiftOS_Setup.ps1
Follow the instructions/prompts.

## License
MIT License © 2025 Mazen Gohar

## Support / Contact
For help or feedback, open an issue on GitHub or contact mizoiology (at) gmail.com

Made with ❤️ for Windows 11 enthusiasts