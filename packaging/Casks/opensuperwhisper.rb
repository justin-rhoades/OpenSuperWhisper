# Homebrew cask for OpenSuperWhisper.
#
# Template — fill in `version` and `sha256` after each notarized release
# (`shasum -a 256 dist/OpenSuperWhisper-<version>.dmg`), then host this file in a tap
# (e.g. my-monkeys/homebrew-tap). See docs/DISTRIBUTION.md.
cask "opensuperwhisper" do
  version "0.0.0"
  sha256 "REPLACE_WITH_DMG_SHA256"

  url "https://github.com/my-monkeys/OpenSuperWhisper/releases/download/#{version}/OpenSuperWhisper-#{version}.dmg",
      verified: "github.com/my-monkeys/OpenSuperWhisper/"
  name "OpenSuperWhisper"
  desc "macOS dictation with local Whisper/Parakeet transcription"
  homepage "https://github.com/my-monkeys/OpenSuperWhisper"

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  app "OpenSuperWhisper.app"

  zap trash: [
    "~/Library/Application Support/ru.starmel.OpenSuperWhisper",
    "~/Library/Preferences/ru.starmel.OpenSuperWhisper.plist",
    "~/Library/Caches/ru.starmel.OpenSuperWhisper",
    "~/Library/Application Support/FluidAudio",
  ]
end
