# AGENTS.md

Guide for coding agents working in `D:\Thesis\Test_app\test_app_1`.

## Project Snapshot
- Stack: Flutter + Dart 3.
- App type: accessibility-first smart cane companion app.
- Main entrypoint: `lib/main.dart`.
- Main layers: `lib/core/`, `lib/services/`, `lib/presentation/`.
- Key concerns: bilingual UI, voice guidance, BLE alerts, GPS/location, readable UI.
- Services commonly use singleton accessors like `.instance`.
- Generated folders/files such as `build/`, `.dart_tool/`, and platform registrants should not be edited unless the task is platform-build specific.

## Repo Rule Files
- No `.cursor/rules/` entries were found.
- No `.cursorrules` file was found.
- No `.github/copilot-instructions.md` file was found.
- This file is the main repository-specific instruction source for agents.

## Repo Map
- `lib/core/config/`: API and app config.
- `lib/core/navigation/`: route constants.
- `lib/core/theme/`: colors, text styles, theme setup.
- `lib/core/utils/`: constants and accessibility helpers.
- `lib/services/`: BLE, speech, TTS, location, Groq, voice orchestration.
- `lib/presentation/screens/`: page-level widgets.
- `lib/presentation/widgets/`: reusable widgets.
- `test/`: widget tests.

## Commands

### Setup / Run
```bash
flutter pub get
flutter doctor
flutter devices
flutter run
flutter run -d <device-id>
```

### Lint / Format
```bash
flutter analyze
dart format .
dart format lib/presentation/screens/home_screen.dart
```

### Test
```bash
flutter test
flutter test test/widget_test.dart
flutter test test/widget_test.dart --plain-name "App loads successfully"
flutter test --name "App loads successfully"
flutter test --reporter expanded
flutter test --coverage
```

### Build
```bash
flutter build apk
flutter build appbundle
flutter build web
flutter build windows
flutter build linux
flutter build macos
flutter build ios
```

## Current Verification Notes
- `flutter analyze` currently passes with info-level deprecation warnings.
- Existing warnings include `withOpacity` usage, deprecated `RadioListTile` APIs, and deprecated `speech_to_text` listen params.
- `flutter test` currently fails in `test/widget_test.dart` because `flutter_blue_plus` is unsupported on the test platform.
- If you touch tests around `HomeScreen` or BLE startup, prefer mocks, guards, or dependency injection over plugin initialization in pure widget tests.

## Architecture Expectations
- Keep the current separation of concerns: shared primitives in `core/`, external integrations in `services/`, UI in `presentation/`.
- Reuse `AppColors`, `AppTextStyles`, `AppConstants`, and `AppRoutes` before introducing new values or strings.
- Put reusable platform logic in services, not directly in widgets.
- Preserve the singleton service pattern unless you are intentionally refactoring a whole area toward dependency injection.
- Keep route names centralized in `lib/core/navigation/app_routes.dart`.

## Code Style

### Imports
- Use package imports for Dart/Flutter SDK and third-party packages.
- Use relative imports for app-local files; that is the established style in this repo.
- Order imports consistently: Dart SDK, package imports, then relative imports.
- Remove unused imports immediately.

### Formatting
- Follow `dart format`; do not manually fight the formatter.
- Prefer trailing commas in multiline constructors and widget trees.
- Keep widget trees vertically structured and readable.
- Prefer `const` whenever possible.
- Prefer `final` for fields and locals that are not reassigned.

### Types
- Use explicit return types on public APIs.
- Use `required` named parameters for non-optional constructor args.
- Prefer concrete types over `dynamic`, except at JSON boundaries.
- Convert external JSON/maps into typed models quickly.
- Keep lightweight data objects immutable where possible.
- Use nullable types only when absence is a real state.

### Naming
- Use `PascalCase` for classes and enums.
- Use `camelCase` for methods, fields, locals, params, and enum values.
- Use `snake_case.dart` for filenames.
- Prefix private members with `_`.
- Prefer domain-revealing names like `VoiceNavigationService` or `AccessibleActionButton`.

## Flutter-Specific Conventions
- In stateful widgets, check `mounted` after `await` before calling `setState`, showing dialogs, or using `ScaffoldMessenger`.
- Keep async setup in lifecycle helpers like `_initializeServices()` or `_fetchLocation()`, not inside `build()`.
- For `ChangeNotifier`, update internal state before `notifyListeners()`.
- Keep visible strings consistent with the screen style; many screens pair Bangla and English text.
- Preserve portrait-only and text-scaling assumptions already configured in `lib/main.dart` unless the task explicitly changes them.

## UI And Accessibility
- Accessibility is not optional here; preserve semantic labels, hints, headers, and large touch targets.
- Reuse constants such as `minTouchTargetSize`, `largeTouchTargetSize`, spacing, and radius tokens.
- Prefer high-contrast, theme-backed colors from `lib/core/theme/`.
- When editing user-facing text on existing screens, keep the bilingual Bangla/English pattern intact.
- Avoid shrinking buttons, icons, or text in ways that work against readability.

## Error Handling
- Wrap plugin, BLE, HTTP, geolocation, speech, and TTS operations in `try/catch`.
- Log developer diagnostics with `debugPrint`.
- Return safe fallbacks like `null`, default messages, or error objects when integrations fail.
- Surface user-facing failures through state, dialogs, or `SnackBar`, not crashes.
- Keep spoken and visible error text short and understandable.
- Guard unsupported platform behavior explicitly, especially in tests and desktop contexts.

## Testing Guidance
- Prefer focused tests over broad plugin-heavy widget tests when possible.
- Avoid direct initialization of platform plugins in tests without mocks or guards.
- For a single test, use `flutter test <file> --plain-name "<test name>"`.
- If you make code more testable, prefer dependency injection or adapter boundaries instead of weakening assertions.

## Security And Config
- Do not add new secrets to source files.
- `lib/core/config/api_config.dart` safely loads the API key from a `.env` file; do not expose or require it in logs/docs/tests.
- If you touch API config, prefer using `.env` or `--dart-define`.
- Be careful about logging full third-party responses.

## Practical Editing Advice
- Check for an existing constant before adding a new magic number.
- If the same visual value appears in multiple places, prefer updating shared theme/constants files.
- Keep comments minimal; the repo mostly uses brief doc comments and readable naming instead of heavy inline commentary.
- Preserve the current straightforward style; do not introduce unnecessary abstractions.

## Default Post-Change Verification
```bash
dart format .
flutter analyze
flutter test
```

If `flutter test` fails because of plugin support, run the most relevant single test file or named test and document the limitation clearly.
