class PrivateIndex < Formula
  desc "Local, privacy-first semantic document indexing and search CLI (pi)"
  homepage "https://github.com/tarunprakash2468/private-index"
  version "0.6.0"
  license "MIT"

  depends_on :macos
  depends_on arch: :arm64

  url "https://github.com/tarunprakash2468/private-index/releases/download/v#{version}/private-index-cli-#{version}-darwin-arm64.tar.gz"
  sha256 "6a5a3346a61c7fe336bd90f5b003cfca7d978ef0a92437ebb4ef5ee17a68e299"

  def install
    bin.install "private-index-cli" => "pi"
    bin.install_symlink bin/"pi" => "private-index"
    bin.install_symlink bin/"pi" => "private-index-cli"

    # Resource bundle containing vocab and tokenizer assets
    if File.directory?("PrivateIndexEngine_PrivateIndexEngine.bundle")
      bin.install "PrivateIndexEngine_PrivateIndexEngine.bundle"
    end

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
    assert_match "Private Index", shell_output("#{bin}/pi help")
    assert_match "Private Index", shell_output("#{bin}/private-index help")
    assert_match "Private Index Database Statistics", shell_output("#{bin}/pi stats")
  end
end
