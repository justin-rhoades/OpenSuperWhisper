# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

OpenSuperWhisper is a macOS (Sonoma 14+) menu-bar dictation app: press a global hotkey, speak, and the transcription is typed into the frontmost app. It's a SwiftUI + AppKit app with C/C++/Rust native dependencies. This is a community fork (`my-monkeys/`) of `Starmel/OpenSuperWhisper`.

## Build & run

```sh
# First time only: clone native deps and install build tools
git submodule update --init --recursive
brew install cmake libomp rust ruby
gem install xcpretty            # optional, prettier build output

./run.sh build      # build only (what CI runs — see .github/workflows/build.yml)
./run.sh            # build, then launch the app with logs in the terminal
```

`run.sh` does much more than `xcodebuild`: it CMake-configures `libwhisper`, fetches sherpa-onnx (`Scripts/fetch-sherpa.sh`), `cargo build`s the Rust `autocorrect-swift` dylib, copies/re-signs `libomp` + `libonnxruntime` into `build/`, resolves Swift packages, **applies the FluidAudio source patches** (`patches/*.patch` — keyword-boosting quality + a Swift 6.3 `Sendable` fix; idempotent, fails loudly if a target moved on a version bump), then builds the `arm64` Debug app into `build/Build/Products/Debug/`. It re-signs with a stable identity (`Scripts/dev-codesign.sh`) so macOS keeps granted TCC permissions (mic / accessibility) across rebuilds. Editing native deps or bumping FluidAudio means re-running the full `./run.sh build`, not just compiling in Xcode.

The default build is **arm64-only**. Intel (x86_64) is a separate release build that excludes SenseVoice (its onnxruntime ships arm64-only).

## Tests

XCTest targets, run via Xcode or:

```sh
xcodebuild test -scheme OpenSuperWhisper -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build -clonedSourcePackagesDirPath SourcePackages
# single class: add -only-testing:OpenSuperWhisperTests/TextInserterTests
```

Tests in `OpenSuperWhisperTests/` are pure-logic unit tests (text chunking, caret-anchor decisions, paste-target detection, custom-dictionary boost terms, diag) — they do not exercise the audio/engine pipeline. `OpenSuperWhisperUITests/` holds the UI tests.

## Release

Notarized Developer ID builds, two DMGs per release (arm64 + x86_64, no universal binary). See `docs/RELEASING.md`. `notarize_app.sh <identity> <arch>` builds → signs → notarizes → DMGs one arch; each arch points `SUFeedURL` at its own Sparkle feed (`appcast.xml` / `appcast-x86_64.xml`).

## Architecture

**Entry point** (`OpenSuperWhisperApp.swift`): `AppMain.main()` checks `CLI.shouldHandle(args)` first — `transcribe`/`bench` run **headless** (no GUI, reuse the configured engine, print to stdout) and never launch the SwiftUI app. Otherwise the SwiftUI `App` runs, showing `OnboardingView` or `ContentView`. `AppDelegate` owns the status-bar item and window lifecycle.

**Transcription engines** — pluggable behind the `TranscriptionEngine` protocol (`Engines/TranscriptionEngine.swift`): `WhisperEngine` (whisper.cpp, default), `FluidAudioEngine` (Parakeet, supports live preview), `SenseVoiceEngine` (sherpa-onnx, arm64-only, behind `#if arch(arm64)`), `GroqEngine` (cloud whisper-large-v3, needs API key). `TranscriptionService` (`@MainActor` singleton) reads `AppPreferences.shared.selectedEngine`, instantiates the right engine on a detached task, and publishes transcription state. The whisper.cpp C API is wrapped in `Whis/` (Swift wrappers over the params/structs), bridged through `Bridge.h`.

**Recording flow**: `ShortcutManager` (via the `KeyboardShortcuts` package + `ModifierKeyMonitor` for single-modifier hotkeys) handles the global hotkey — tap to toggle, or hold-to-record (0.3s threshold). It drives the `IndicatorWindowManager` (the on-screen recording indicator) and `AudioRecorder`. After transcription, `TextInserter` types the result into the frontmost app by **synthesizing Unicode keyboard events** (`CGEvent`) — it never touches the pasteboard, avoiding any clipboard race. `TranscriptionQueue` processes drag-and-dropped files serially.

**Settings/preferences**: `AppPreferences` (singleton) wraps `UserDefaults` via the `@UserDefault` / `@OptionalUserDefault` property wrappers. Secrets (Groq API key) go through `Keychain`, never UserDefaults. `Settings` is the per-transcription config passed into `transcribeAudio(url:settings:)`.

**LLM cleanup** (optional, post-transcription): `LLMPostProcessor.process(_:bundleID:)` runs the text through a local LLM for general prose cleanup and/or **app-aware formatting** (per-app `AppContextProfile` rules keyed by the frontmost bundle id — e.g. "at Rob" → "@Rob" in Slack). Both are independent opt-in toggles feeding one LLM pass; output is length-guarded so a misbehaving model can't mangle the transcription. The LLM call sits behind the `LLMCleanupBackend` protocol with two impls: `OllamaBackend` (external server) and `BuiltInLlamaBackend` (embedded llama.cpp + a downloaded Qwen2.5 GGUF via `LLMModelManager`, wrapped by `Llama/LlamaContext.swift`). Backend is chosen by the `aiBackend` pref.

**Native dependencies**: `libwhisper/whisper.cpp` (git submodule, CMake) and `libwhisper/llama.cpp` (git submodule, CMake — built in the *same* libwhisper project so it **shares whisper's `ggml` target**, avoiding duplicate symbols; added via `add_subdirectory(llama.cpp)` after whisper), `asian-autocorrect` (git submodule, Rust → `libautocorrect_swift.dylib` via `AutocorrectWrapper`), sherpa-onnx + onnxruntime (fetched/vendored under `vendor/`), FluidAudio (Swift package, patched at build time). The CMake-generated `libwhisper.xcodeproj` static libs (`libwhisper.a`, `libggml*.a`, `libllama.a`) are linked into the app by **path** from `BUILT_PRODUCTS_DIR` via cross-project reference proxies — the proxies' remote GUIDs are regenerated per CMake run and dangle harmlessly, so never point one at a `PBXNativeTarget` (it crashes project load).

## Key invariants — do not break these

- **Window sizing has exactly ONE authority: SwiftUI.** Geometry is `.frame(width: 450).frame(minHeight: 400, maxHeight: 900)` + `.windowResizability(.contentSize)`. **Never** also set `minSize`/`maxSize` or implement `windowWillResize` in AppKit — a second sizing authority fights SwiftUI's `updateAnimatedWindowSize`, recursing into a stack-overflow crash (#11). See the long comments in `OpenSuperWhisperApp.swift`.
- The recording indicator (`Indicator/`) auto-sizes to its content and anchors to the caret (or screen-top in Notch mode); reposition is guarded against a layout-loop recursion (`isRepositionPending`). Tread carefully when changing indicator layout.
- `TranscriptionResult.noSpeech` ("No speech detected…") is shown as feedback but must **never** be typed into the focused field.

## Diagnostics

`Utils/Diag.swift` traces the hotkey/record hot path via `os.Logger` (subsystem `fr.my-monkey.opensuperwhisper`), which survives a force-quit of a hung app. After a freeze:

```sh
log show --predicate 'subsystem == "fr.my-monkey.opensuperwhisper"' --last 30m --info --debug
```

A dangling `▶ name` with no matching `◀` names the blocking call. On by default in DEBUG; in release, enable with `defaults write fr.my-monkey.opensuperwhisper diagnosticLogging -bool YES`.
