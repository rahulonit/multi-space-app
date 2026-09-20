# PINGGO Windows - Native Windows Desktop Application

PINGGO for Windows is a native desktop application built with **C# (.NET 8)**, **WinUI 3 (Windows App SDK)**, and Microsoft Edge **WebView2**, featuring modern Windows 11 Fluent Design (Mica / Acrylic materials, dark/light themes), isolated multi-account social portals, built-in private browser with native AdBlocker, AI thread co-pilot, side-by-side split view, Ctrl+K command palette, and Windows Hello biometric security.

---

## Architecture & Framework Highlights

1. **Native Windows 11 UI**:
   - Built on **WinUI 3 / Windows App SDK 1.5**, Microsoft's official modern native desktop UI framework.
   - Standardized 64px Global Header with Brand, segmented navigation pill (`[ Platform ] [ Overview ] [ Inbox ] [ Browser ]`), SECURE pill, search, and profile controls.
   - Smooth Mica backdrops and responsive sidebar navigation.

2. **Isolated Multi-Account Portals**:
   - Powered by Microsoft Edge **WebView2** (`CoreWebView2`).
   - Each account is mapped to a dedicated user data folder under `%AppData%\PINGGO\Profiles\{accountID}`.
   - Guarantees 100% cookie, cache, local storage, and session isolation between multiple accounts on the same platform (e.g. Work WhatsApp vs. Personal WhatsApp).

3. **Built-in Private Browser with Native AdBlocker**:
   - Safari/Edge-style multi-tab bar with live session retention.
   - Network-level ad & tracker blocking via `CoreWebView2WebResourceRequested` + cosmetic stylesheet suppression.
   - Search omnibar, Reader Mode, and quick favorites grid.
   - Session persistence restoring all tabs across restarts (`%AppData%\PINGGO\browser_session.json`).

4. **Split View Dual-Workspace**:
   - Side-by-side split portal view with independent WebView2 instances.
   - 1-Click `⇄` pane swap button to exchange workspaces seamlessly.

5. **AI Thread Co-Pilot & Stealth Replies**:
   - Direct REST integration with Google Gemini and OpenAI ChatGPT endpoints.
   - Local fallback smart engine for zero-telemetry offline reply drafting, translation, and sentiment classification.

6. **Windows Hello & PIN Security**:
   - Biometric authentication via `Windows.Security.Credentials.UI.UserConsentVerifier` (Fingerprint, Face, or PIN).
   - Inactivity auto-lock timer with frosted glass lock screen.

---

## Prerequisites for Building

- **Windows 10 (version 1809+) or Windows 11**
- **.NET 8.0 SDK** ([Download .NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0))
- **Visual Studio 2022** (v17.8 or newer) with the following workloads:
  - *.NET Desktop Development*
  - *Windows App SDK C# Templates* (included in Visual Studio Installer)
- **WebView2 Runtime** (pre-installed on all Windows 10 & 11 PCs)

---

## Building and Running

### Option 1: Via Visual Studio 2022 (Recommended)
1. Double-click `windows/PINGGO.sln` to open the solution in Visual Studio 2022.
2. Select `Release` (or `Debug`) and `x64` in the top configuration dropdown.
3. Set `PINGGO` as the Startup Project.
4. Press `F5` (or `Ctrl+F5`) to build and run the native application.

### Option 2: Via Windows Command Prompt or Terminal
To build:
```cmd
cd windows\Scripts
build.bat
```

To run directly via .NET CLI:
```cmd
cd windows\PINGGO
dotnet run -c Debug -p:Platform=x64
```

### Option 3: Publishing a Standalone Executable (.exe)
Run the PowerShell build script:
```powershell
cd windows\Scripts
.\build.ps1 -Configuration Release -Platform x64
```
The self-contained standalone application will be generated in `dist/windows/PINGGO.exe` (runs on any Windows 10/11 64-bit PC without requiring pre-installed runtimes).

---

## Keyboard Shortcuts

- `Ctrl+K`: Open Command Palette / Quick Workspace Switcher
- `Ctrl+T`: Open New Browser Tab
- `Ctrl+\`: Toggle Side-by-Side Split View
- `Ctrl+L`: Lock PINGGO immediately
- `Enter`: Navigate in Omnibar / Search in Inbox
