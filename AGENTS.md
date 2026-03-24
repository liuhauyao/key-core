# AGENTS.md

## Cursor Cloud specific instructions

### Project overview
Key Core (密枢) is a cross-platform Flutter desktop app for managing AI API keys. It uses SQLite (embedded via FFI), AES-256-GCM encryption, and stores sensitive data in the platform keychain. There is no backend server.

### Prerequisites
- **Flutter SDK** is installed at `/opt/flutter` and added to `PATH` via `~/.bashrc`.
- **Linux desktop dependencies**: `libgtk-3-dev`, `ninja-build`, `libsqlite3-dev`, `liblzma-dev`, `libayatana-appindicator3-dev`, `g++-14`, `clang`, `cmake`, `pkg-config`.
- A `libstdc++.so` symlink and `ld`/`ar` symlinks in `/usr/lib/llvm-18/bin/` are needed for clang-18 to link correctly (see setup notes below).

### Quick reference (standard commands from README)
- **Install deps**: `flutter pub get`
- **Lint/analyze**: `flutter analyze`
- **Tests**: `flutter test`
- **Build (Linux)**: `flutter build linux`
- **Run (Linux)**: `flutter run -d linux` or launch the built binary at `build/linux/x64/release/bundle/key_core`

### Non-obvious gotchas

1. **Missing `linux/` platform directory**: The repo ships without a `linux/` directory. Run `flutter create --platforms=linux .` to generate it before building.

2. **Missing `assets/images/` directory**: The `pubspec.yaml` references `assets/images/` but the directory doesn't exist in the repo. Create it (`mkdir -p assets/images`) or the build/test will fail with "unable to find directory entry".

3. **Clang linker setup**: On this VM, clang-18 can't find `ld`, `ar`, etc. in `/usr/lib/llvm-18/bin/`. Symlinks are needed:
   ```
   sudo ln -sf /usr/bin/ld /usr/lib/llvm-18/bin/ld
   sudo ln -sf /usr/bin/ar /usr/lib/llvm-18/bin/ar
   sudo ln -sf /usr/lib/x86_64-linux-gnu/libstdc++.so.6 /usr/lib/x86_64-linux-gnu/libstdc++.so
   ```

4. **Stale test file**: `test/widget_test.dart` references `package:ai_key_manager` and `MyApp` which don't exist. This test will always fail — it's a leftover from the Flutter template and is not related to the actual app code (`package:key_core` / `KeyCoreApp`).

5. **`path_provider` on headless Linux**: The app logs `MissingPlatformDirectoryException` when it can't find the application documents directory. This doesn't prevent the GUI from launching but means config caching fails silently. Setting `XDG_DATA_HOME` and `XDG_CONFIG_HOME` environment variables may help.

6. **Display server**: Running the GUI requires a display. Use `DISPLAY=:1` (the VM's Xvfb). Tests (`flutter test`) run headlessly without a display.
