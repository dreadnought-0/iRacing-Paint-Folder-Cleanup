# iRacing-Paint-Folder-Cleanup
After every iRacing session, your paint folder quietly fills up with leftover liveries from every car you drove near. Trading Paints promises to clean them up — but more often than not, those files just sit there, accumulating session after session.

iRacing Paint Folder Cleaner fixes that with one click. Scan your paint folder, preview exactly what will be removed, and clean it out in seconds. Your own car folders stay untouched — only the abandoned files left behind by other drivers are removed.

### Features:

- One-click cleanup — scan and delete leftover paint files instantly
- Safe preview — see exactly what will be deleted before anything is removed
- Auto-detects your paint folder — works out of the box, no configuration needed
- Your files stay safe — only removes files inside car folders, never the folders themselves
- Runs on Windows — no installation required, just PowerShell (already on your PC)
- 7-day offline grace period — works even without an internet connection
  
### Requirements
- Windows 10 or 11
- PowerShell 5.1 or later (built into Windows — nothing to install)
- iRacing installed with Trading Paints having run at least once
- Internet connection for first activation

### Step 1 — Download and Extract

Download the zip from your website and extract it anywhere, e.g.:
```
C:\Program Files\iRacing Paint Cleaner\
```

### Step 2 — Unblock the Script

Windows blocks scripts downloaded from the internet by default.

1. Right-click `iRacing-Paint-Cleaner.ps1`
2. Select **Properties**
3. Check the **Unblock** box at the bottom → click **OK**

> If there is no Unblock checkbox, the file is already trusted — skip this step.

### Step 3 — Launch the App

Double-click `Launch.bat`.

If Windows shows a SmartScreen warning, click **More info → Run anyway**.

### Step 4 — Activate Your License

On first launch, an activation screen appears. Paste the license key from your purchase confirmation email and click **Activate**.

- Your key is locked to this machine after activation
- If you get a new PC or reinstall Windows, contact support to have your key reset

### Step 5 — Clean Your Paint Files

After activation the main app opens.

1. The paints folder is auto-detected at `C:\Users\<you>\Documents\iRacing\paint`
   — use **Browse** if yours is in a different location
2. Click **Scan Folder** to preview what will be deleted
3. Click **Clean Paint Files** and confirm
4. Car folders are kept — only the files inside them are removed

### Offline Use

If you have no internet connection, the app uses the last successful license check. You have a **7-day grace period** before a connection is required again.
