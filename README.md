# Multispace for macOS

A native SwiftUI starting point for an all-in-one social chat app. It has a responsive sidebar with WhatsApp, Instagram, Telegram, and Facebook, plus a button to add more platforms. Open a platform to edit its name, icon, color, and website or remove it; the same actions are available by right-clicking its sidebar entry. It also includes local direct messages, a community feed, people search, profile editing, and local persistence.

## Build and run

Requires macOS 14 or newer and the Swift 6 toolchain. Run:

```sh
./Scripts/build-app.sh
open dist/Multispace.app
```

You can also open `Package.swift` in Xcode to edit and run the project there. This machine has Command Line Tools rather than full Xcode; the build script selects its working macOS SDK automatically.

## Current scope

Selecting a platform opens its official website in the right pane. The website uses its own login flow when there is no session; WebKit stores that site's session data locally. Some platforms may still restrict embedded browsers or require their own app. The toolbar's **Open in browser** button provides a fallback. Multispace does not read passwords or convert a website login into a separate API connection.

The Home dashboard watches the embedded website sessions for visible chat-list previews, website alerts, and unread numbers shown in page titles. It displays whatever those portals expose after sign-in. The previews stay in app memory and are cleared when the app quits or a platform is removed; they are not written to `data.json`. Website markup varies and can change, so a platform may show no previews even when it has activity. The dashboard is not a complete notification inbox, and it cannot read activity from a separate native app or Safari session. Account-level message sync for personal and business accounts requires separate authorized integrations for each platform.

The embedded WebKit session is separate from Safari's cookies, so an account already signed in to Safari may ask for a one-time sign-in inside Multispace. The app identifies the embedded view as a current Safari-compatible browser for services that otherwise show an inaccurate “update Safari” screen.

This is a local prototype. The added app list is stored in local app preferences. The local messages, posts, spaces, channels, likes, and profile changes persist in `~/Library/Application Support/Multispace/data.json` on this Mac. The starter people and conversations are sample data. Full cross-platform message sync, push notifications, media, and calling need separate integrations.

Platform logos in `Sources/Multispace/Resources` were obtained from the platforms' own website favicons. They identify the linked services; Multispace is not affiliated with them.
