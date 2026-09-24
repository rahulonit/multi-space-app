# Multispace for macOS

A native SwiftUI starting point for an all-in-one social chat app. It has a responsive sidebar with WhatsApp, Instagram, Telegram, and Facebook, plus a button to add more platforms. Open a platform to edit its name, icon, color, and website or remove it; the same actions are available by right-clicking its sidebar entry. Each platform can hold multiple separately signed-in accounts.

## Build and run

Requires macOS 14 or newer and the Swift 6 toolchain. Run:

```sh
./Scripts/build-app.sh
open dist/Multispace.app
```

You can also open `Package.swift` in Xcode to edit and run the project there. This machine has Command Line Tools rather than full Xcode; the build script selects its working macOS SDK automatically.

## Current scope

Selecting a platform opens its official website in the right pane. The website uses its own login flow when there is no session; WebKit stores that site's session data locally. Some platforms may still restrict embedded browsers or require their own app. The toolbar's **Open in browser** button provides a fallback. Multispace does not read passwords or convert a website login into a separate API connection.

Use the account menu beside a platform name to add or rename accounts. When a platform has more than one account, each appears directly beneath it in the sidebar; click a name to switch. Home marks the active account. In the compact sidebar, right-click the platform icon to choose an account. The selected account also carries into Feeds for platforms with feeds. The first account retains the existing website session. Each added account uses a separate persistent WebKit data store, so signing into one account does not replace another. Added accounts can be removed from the account menu; their WebKit website data is cleared. The Home dashboard shows one card per account and watches each embedded session for visible chat-list previews, website alerts, and unread numbers shown in page titles. Inbox groups the available previews by platform and account. Feeds opens the selected Instagram, Facebook, X, LinkedIn, or TikTok web feed. The previews stay in app memory and are cleared when the app quits or an account is removed; they are not written to `data.json`. Website markup varies and can change, so a platform may show no previews even when it has activity. Inbox is not a complete notification inbox, and it cannot read activity from a separate native app or Safari session. Account-level message sync for personal and business accounts requires separate authorized integrations for each platform.

The sidebar plus button opens a searchable platform picker with official logos. It shows platforms already in the sidebar and supports a custom HTTPS website with name and URL validation.

The embedded WebKit session is separate from Safari's cookies, so an account already signed in to Safari may ask for a one-time sign-in inside Multispace. The app identifies the embedded view as a current Safari-compatible browser for services that otherwise show an inaccurate “update Safari” screen.

This is a local prototype. The added app and account names are stored in local app preferences. The earlier local messages, posts, spaces, channels, likes, and profile changes persist in `~/Library/Application Support/Multispace/data.json` on this Mac, but no longer appear in the cross-platform Feed and Inbox. Full cross-platform message sync, push notifications, media, and calling need separate integrations.

Settings (gear button or ⌘,) has General, Launch, Interaction, Subscription, and About pages. Appearance, accent color, compact layout, startup destination, website checks, check delay, and dashboard alert visibility are saved in local preferences. English is the current interface language. Native app launching and purchases are not configured in this build; their settings show that status without offering an inactive purchase button.

## AI providers

PINGGO can use Google Gemini, OpenAI, Ollama, or its built-in local Smart Engine. Connect Gemini or OpenAI from **Settings → AI Assistant** with an API credential and validate it before use. On macOS credentials are stored in Keychain; on Windows they are stored in Credential Locker. Older plaintext credentials are migrated and removed from serialized preferences on the next launch. Website logins and ChatGPT/Gemini consumer subscriptions are deliberately kept separate from API authentication.

To connect Gemini, open [Google AI Studio](https://aistudio.google.com/app/apikey), sign in, create or copy an API key, paste it into PINGGO, and select **Validate & Connect**. To connect OpenAI, open the [OpenAI Platform API keys page](https://platform.openai.com/api-keys), create a project API key, copy it, paste it into PINGGO, and validate it. OpenAI API usage may require separate API billing even when the user has a ChatGPT subscription.

Provider status in the AI Assistant distinguishes validated hosted access from the local Smart Engine. Conversation content is sent to a hosted provider only when that provider is connected, validated, selected, and enabled.

Platform logos in `Sources/Multispace/Resources` were obtained from the platforms' own website favicons. They identify the linked services; Multispace is not affiliated with them.
