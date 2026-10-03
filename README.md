# AksharBuddy — Local Wi-Fi Setup

## 1. Keep the Project Folder Together

Do not separate the APK, backend, or scripts.

The folder should contain files such as:

- `Start AksharBuddy.cmd`
- `Setup AksharBuddy.ps1`
- `Enable LAN Firewall.ps1`
- `AksharBuddy.apk`
- Backend files

This is a separate testing version. Do not modify the original `hadeel_major project`.

## 2. First-Time Setup

Connect the laptop to the internet.

Open PowerShell inside the AksharBuddy folder and run:

```powershell
powershell -ExecutionPolicy Bypass -File ".\Setup AksharBuddy.ps1"
```

This installs/checks the required backend and OCR dependencies.

You normally need to do this only once.

## 3. Connect Phone and Laptop

Connect both devices to the **same Wi-Fi or hotspot**.

Example:

```text
Laptop → Home Wi-Fi
Phone  → Home Wi-Fi
```

Home Wi-Fi or a personal hotspot is recommended for testing.

## 4. Set the Windows Network to Private

Go to:

**Settings → Network & Internet → Wi-Fi → Connected Network**

Select:

**Private Network**

## 5. Allow the Backend Through Firewall

If the phone cannot connect, open PowerShell as **Administrator** inside the project folder and run:

```powershell
powershell -ExecutionPolicy Bypass -File ".\Enable LAN Firewall.ps1"
```

This allows AksharBuddy to use port `5000` on the local network.

Usually, this is required only once.

## 6. Start AksharBuddy

Double-click:

```text
Start AksharBuddy.cmd
```

Keep this window open while using the app.

The launcher will display an address similar to:

```text
http://192.168.29.68:5000
```

The IP address may change when you change Wi-Fi networks, so always use the address shown by the launcher.

## 7. Install the APK

Transfer `AksharBuddy.apk` to the phone using Telegram, Quick Share, USB, Drive, or another method.

Open the APK and install/update the app.

If Android asks for permission to install from that source, allow it temporarily.

## 8. Connect the App to the Laptop

Open AksharBuddy on the phone.

Go to:

**Settings → Laptop connection**

Enter the address shown by the laptop launcher, for example:

```text
http://192.168.29.68:5000
```

Then tap:

**Save and check connection**

If the connection succeeds, AksharBuddy is ready to use.

## Daily Use

After the first-time setup, you normally only need to:

1. Connect the phone and laptop to the same Wi-Fi/hotspot.
2. Double-click `Start AksharBuddy.cmd`.
3. Keep the launcher window open.
4. Open AksharBuddy on the phone.
5. Update the Laptop Connection address if the IP has changed.

**USB is not required for normal use.**
