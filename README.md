# Multispace for macOS

A native SwiftUI starting point for an all-in-one social chat app. It has a single sidebar with WhatsApp, Instagram, Telegram, and Facebook, plus a button to add more platforms. It also includes local direct messages, a community feed, people search, profile editing, and local persistence.

## Build and run

Requires macOS 14 or newer and the Swift 6 toolchain. Run:

```sh
./Scripts/build-app.sh
open dist/Multispace.app
```

You can also open `Package.swift` in Xcode to edit and run the project there. This machine has Command Line Tools rather than full Xcode; the build script selects its working macOS SDK automatically.

## Current scope

This is a local prototype. Adding a social app places it in the sidebar; it does not connect a real account or sync messages. The added app list is stored in local app preferences. The local messages, posts, spaces, channels, likes, and profile changes persist in `~/Library/Application Support/Multispace/data.json` on this Mac. The starter people and conversations are sample data. Account integrations, multi-user sync, media, notifications, and calling need separate implementation.
