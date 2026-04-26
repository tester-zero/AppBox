# AppBox

AppBox is a modern Android application built with Flutter that allows users to create custom workspaces (app groups) and quickly launch their most important apps from a clean, minimal interface.

Instead of a traditional app drawer, AppBox focuses on organization, speed, and personalization. Users can group apps into meaningful workspaces such as Work, Social, Media, or Study, and access them with fewer taps.

---

## Features

### Workspace-Based Organization

* Create custom workspaces (folders inside the app)
* Add selected apps to each workspace
* Each workspace has:

  * Custom name
  * Icon
  * Accent color

### Fast App Launching

* Launch apps directly from workspace tiles
* Pre-warmed intents for faster startup
* Visual feedback while launching apps

### Installed Apps Picker

* Displays all user-installed apps (excluding system apps)
* Paginated loading for performance
* Smooth scrolling grid layout
* Multi-select support

### Persistent Storage

* Workspaces are saved locally using SharedPreferences
* Data is restored on app launch

### Dynamic UI System

* Fully responsive layout using LayoutScale
* Dark and Light mode support
* Consistent design system with reusable palette

### Experimental Features System (EX)

* Opt-in system for testing upcoming features
* Dedicated screen explaining experimental functionality
* Feature flag stored locally
* Foundation for advanced features such as Smart Suggestions

---

## Upcoming Features

* Smart Suggestions (based on usage, time of day, and recency)
* Drag and reorder workspaces
* Usage-based app sorting inside workspaces
* Search bar for faster app discovery
* Workspace deletion with confirmation flow
* Icon and color customization UI improvements

---

## Tech Stack

* Flutter (Dart)
* Android Native (Kotlin) via MethodChannel
* SharedPreferences for local persistence

---

## Architecture Overview

### Flutter Layer

* UI rendering
* State management (setState, ValueNotifier)
* Navigation
* Persistence handling

### Native Android Layer (Kotlin)

* Fetch installed applications
* Convert app icons to byte arrays
* Launch apps using intents
* Cache:

  * App list (in-memory)
  * Icons (LruCache)
  * Launch intents

### Communication

* MethodChannel: `com.appbox.app/installed_apps`

---

## Project Structure

```
lib/
 ├── main.dart                # Core app logic and UI
 ├── models/                  # Data models (logical separation)
 ├── services/                # AppService (platform channel)
 ├── widgets/                 # Reusable UI components
 └── screens/                 # Screens (Main, Create Workspace, EX)

android/
 └── MainActivity.kt          # Native Android implementation
```

---

## Permissions

The app uses the following permission:

```
android.permission.QUERY_ALL_PACKAGES
```

This is required to:

* Retrieve the list of installed apps
* Allow users to select apps for workspaces

Note:
This permission is sensitive and may require justification during Play Store submission.

---

## Performance Optimizations

* App list caching to avoid repeated native calls
* Icon caching using LruCache
* Pagination for large app lists
* Background parsing using `compute`
* Intent pre-warming for faster app launches

---

## How It Works

1. App fetches installed apps from native Android layer
2. Data is parsed and stored in memory
3. User creates workspaces and selects apps
4. Workspaces are saved locally
5. Apps can be launched instantly from UI

---

## Build Instructions

### Prerequisites

* Flutter SDK
* Android Studio or compatible IDE
* Android device or emulator

### Run the project

```
flutter pub get
flutter run
```

### Build APK

```
flutter build apk
```

### Build App Bundle (Recommended for Play Store)

```
flutter build appbundle
```

---

## Known Limitations

* Requires special permission for full app visibility
* No cloud sync (local storage only)
* Experimental features are optional and may be unstable

---

## Future Improvements

* Replace SharedPreferences with a structured database
* Add analytics for smarter suggestions
* Improve accessibility and animations
* Add backup/restore functionality
* Optimize icon loading further

---

## License

This project is for learning and development purposes. You can modify and extend it as needed.

---

## Author

Developed as a custom Flutter-based Android application focusing on productivity and minimal UI design.
