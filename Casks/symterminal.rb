cask "symterminal" do
  version "0.2.0"
  sha256 "c3e6d35b5263448098f8f0232475733734ff7c66bfe0d63f6dfa94dd986f99d2"

  url "https://github.com/danieljustus/symaira-terminal/releases/download/v#{version}/SymairaTerminal-#{version}.dmg"
  name "Symaira Terminal"
  desc "Native macOS terminal built for the Human-AI era"
  homepage "https://github.com/danieljustus/symaira-terminal"

  livecheck do
    url "https://github.com/danieljustus/symaira-terminal/releases/latest"
    strategy :header_match
    regex(/SymairaTerminal-(\d+(?:\.\d+)*)\.dmg/i)
  end

  depends_on macos: :sonoma

  app "SymairaTerminal.app"

  zap trash: [
    "~/Library/Application Support/SymairaTerminal",
    "~/Library/Preferences/com.symaira.terminal.plist",
    "~/Library/Caches/com.symaira.terminal",
  ]
end
