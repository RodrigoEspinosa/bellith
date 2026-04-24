cask "bellith" do
  version "0.1.0"
  sha256 :no_check # replaced per-release by the release workflow

  url "https://github.com/RodrigoEspinosa/bellith/releases/download/v#{version}/Bellith-#{version}.dmg",
      verified: "github.com/RodrigoEspinosa/bellith/"
  name "Bellith"
  desc "Native macOS terminal emulator built on Ghostty's rendering engine"
  homepage "https://github.com/RodrigoEspinosa/bellith"

  depends_on macos: ">= :sonoma"

  app "Bellith.app"

  # CLI helper embedded in the app bundle. Symlinking it here mirrors what
  # most terminal casks do (iTerm2, Alacritty, Kitty) so `bellith` is on $PATH.
  binary "#{appdir}/Bellith.app/Contents/Resources/bellith"

  zap trash: [
    "~/Library/Preferences/com.rec.bellith.plist",
    "~/Library/Saved Application State/com.rec.bellith.savedState",
    "~/Library/Caches/com.rec.bellith",
    "~/Library/HTTPStorages/com.rec.bellith",
  ]

  uninstall quit: "com.rec.bellith"
end
