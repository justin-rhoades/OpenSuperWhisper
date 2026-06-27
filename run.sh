#!/bin/zsh

JUST_BUILD=false
if [[ "$1" == "build" ]]; then
    JUST_BUILD=true
fi

# Patch FluidAudio's vocabulary rescorer to prefer longer matching spans
# (keyword boosting quality, e.g. "My-Monkey" matched as one term), and mark
# AsrManager as @unchecked Sendable so the pinned 0.11.0 checkout compiles under
# the Swift 6.3+ toolchain (the actor already accesses it via nonisolated(unsafe),
# so this asserts no guarantee the author wasn't already relying on). Idempotent;
# fails loudly if a target moved (so a FluidAudio bump can't silently skip it).
apply_fluidaudio_patches() {
    local checkout="SourcePackages/checkouts/FluidAudio"

    if [[ ! -d "$checkout" ]]; then
        echo "Missing FluidAudio source checkout: $checkout"
        exit 1
    fi

    # name | patch file | target file (relative to checkout) | sentinel grep
    apply_one_patch \
        "vocabulary rescorer" \
        "patches/fluidaudio-vocabulary-rescorer.patch" \
        "$checkout/Sources/FluidAudio/ASR/CustomVocabulary/Rescorer/VocabularyRescorer+TokenRescoring.swift" \
        "wordTimings.count >= spanLength"

    apply_one_patch \
        "AsrManager Sendable" \
        "patches/fluidaudio-asrmanager-sendable.patch" \
        "$checkout/Sources/FluidAudio/ASR/AsrManager.swift" \
        "public final class AsrManager: @unchecked Sendable"
}

# apply_one_patch <name> <patch_file> <target> <sentinel>
# Applies a -p1 patch into the FluidAudio checkout, idempotently. The sentinel is
# a string that is present iff the patch is already applied.
apply_one_patch() {
    local name="$1" patch_file="$2" target="$3" sentinel="$4"
    local checkout="SourcePackages/checkouts/FluidAudio"

    if [[ ! -f "$patch_file" ]]; then
        echo "Missing FluidAudio patch: $patch_file"
        exit 1
    fi

    if [[ ! -f "$target" ]]; then
        echo "Missing FluidAudio source checkout: $target"
        exit 1
    fi

    if grep -qF "$sentinel" "$target"; then
        echo "FluidAudio $name patch already applied."
        return
    fi

    echo "Applying FluidAudio $name patch..."
    patch --silent --forward -d "$checkout" -p1 < "$patch_file"
    if [[ $? -ne 0 ]] && ! grep -qF "$sentinel" "$target"; then
        echo "Failed to apply FluidAudio $name patch."
        exit 1
    fi
}

# Configure libwhisper
echo "Configuring libwhisper..."
cmake -G Xcode -B libwhisper/build -S libwhisper
if [[ $? -ne 0 ]]; then
    echo "CMake configuration failed!"
    exit 1
fi

./Scripts/fetch-sherpa.sh

echo "Building autocorrect-swift..."
mkdir -p build
cargo build -p autocorrect-swift --release --target aarch64-apple-darwin --manifest-path=asian-autocorrect/Cargo.toml
cp ./asian-autocorrect/target/aarch64-apple-darwin/release/libautocorrect_swift.dylib ./build/libautocorrect_swift.dylib
install_name_tool -id "@rpath/libautocorrect_swift.dylib" ./build/libautocorrect_swift.dylib
codesign --force --sign - ./build/libautocorrect_swift.dylib
if [[ $? -ne 0 ]]; then
    echo "Cargo build failed!"
    exit 1
fi

echo "Copying libomp.dylib..."
# Homebrew's libomp.dylib is read-only (0444); -f unlinks any read-only
# destination from a prior build, and chmod makes the copy writable so the
# install_name_tool / codesign steps below can modify it cleanly.
cp -f /opt/homebrew/opt/libomp/lib/libomp.dylib ./build/libomp.dylib
chmod u+w ./build/libomp.dylib
install_name_tool -id "@rpath/libomp.dylib" ./build/libomp.dylib
codesign --force --sign - ./build/libomp.dylib

echo "Copying libonnxruntime.dylib..."
cp vendor/onnxruntime/libonnxruntime.1.24.4.dylib ./build/libonnxruntime.1.24.4.dylib
ln -sf libonnxruntime.1.24.4.dylib ./build/libonnxruntime.dylib
codesign --force --sign - ./build/libonnxruntime.1.24.4.dylib

# Resolve Swift packages so the FluidAudio checkout exists, then patch it.
echo "Resolving Swift packages..."
RESOLVE_OUTPUT=$(xcodebuild -resolvePackageDependencies -scheme OpenSuperWhisper -derivedDataPath build -clonedSourcePackagesDirPath SourcePackages -skipPackagePluginValidation -skipMacroValidation 2>&1)
if [[ $? -ne 0 ]]; then
    echo "$RESOLVE_OUTPUT"
    echo "Swift package resolution failed!"
    exit 1
fi

apply_fluidaudio_patches

# Build the app
echo "Building OpenSuperWhisper..."
BUILD_OUTPUT=$(xcodebuild -scheme OpenSuperWhisper -configuration Debug -jobs 8 -derivedDataPath build -quiet -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation -UseModernBuildSystem=YES -clonedSourcePackagesDirPath SourcePackages -skipUnavailableActions CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO OTHER_CODE_SIGN_FLAGS="--entitlements OpenSuperWhisper/OpenSuperWhisper.entitlements" build 2>&1)

# sudo gem install xcpretty
if command -v xcpretty &> /dev/null
then
    echo "$BUILD_OUTPUT" | xcpretty --simple --color
else
    echo "$BUILD_OUTPUT"
fi

# Check if build output contains BUILD FAILED or if the command failed
if [[ $? -eq 0 ]] && [[ ! "$BUILD_OUTPUT" =~ "BUILD FAILED" ]]; then
    echo "Building successful!"
    # Re-sign with a stable identity so macOS keeps granted TCC permissions
    # across rebuilds (no-op / ad-hoc fallback when no identity is available).
    "$(dirname "$0")/Scripts/dev-codesign.sh" "./Build/Build/Products/Debug/OpenSuperWhisper.app" || true
    if $JUST_BUILD; then
        exit 0
    fi
    echo "Starting the app..."
    # Remove quarantine attribute if exists
    xattr -d com.apple.quarantine ./Build/Build/Products/Debug/OpenSuperWhisper.app 2>/dev/null || true
    # Run the app and show logs
    ./Build/Build/Products/Debug/OpenSuperWhisper.app/Contents/MacOS/OpenSuperWhisper
else
    echo "Build failed!"
    exit 1
fi 