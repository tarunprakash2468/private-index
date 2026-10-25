class PrivateIndex < Formula
  desc "Local, privacy-first semantic document indexing and search CLI (pi)"
  homepage "https://github.com/tarunprakash2468/private-index"
  version "0.2.0"
  license "MIT"

  depends_on :macos
  depends_on arch: :arm64

  url "https://github.com/tarunprakash2468/private-index/releases/download/v#{version}/private-index-cli-#{version}-darwin-arm64.tar.gz"
  sha256 "bb09dc104249a0192035d01cdd3a498409312456d659d4a5e92ffb198300f0cb"

  def install
    bin.install "private-index-cli" => "pi"
    bin.install_symlink bin/"pi" => "private-index"
    bin.install_symlink bin/"pi" => "private-index-cli"

    # Shell autocompletions
    if File.directory?("completions")
      zsh_completion.install "completions/zsh/_pi" => "_pi"
      bash_completion.install "completions/bash/pi.bash" => "pi"
      fish_completion.install "completions/fish/pi.fish" => "pi.fish"
    end

    # Core ML Embedding Model
    if File.directory?("models/all-MiniLM-L6-v2.mlmodelc")
      pkgshare.install "models/all-MiniLM-L6-v2.mlmodelc"
    end
  end

  test do
    assert_match "pi — Private Index", shell_output("#{bin}/pi help")
    assert_match "pi — Private Index", shell_output("#{bin}/private-index help")
  end
end
