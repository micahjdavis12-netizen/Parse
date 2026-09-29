# Parse

Your code, translated.

Parse is a Mac app. Click a code editor and it reads that file, then explains each line in English.

## Download

You need an Apple silicon Mac on macOS 26 or later.

1. Open the [latest release](https://github.com/micahjdavis12-netizen/Parse/releases/latest) and download `Parse.zip`.
2. Unzip it and move `Parse` into Applications.
3. The first time you open it, Control-click `Parse` and choose Open. macOS asks because this copy is not on the App Store.
4. In System Settings, allow Accessibility for Parse. It needs that once, so it can read the editor you click.

The download is not tied to one person’s signing certificate. Anyone on a matching Mac can run it.

## Build it yourself

Open `Parse.xcodeproj` in Xcode and press Run. The build puts `Parse` in your Applications folder.
