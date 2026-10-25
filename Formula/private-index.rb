class PrivateIndex < Formula
  desc "Local, privacy-first semantic document indexing and search CLI (pi)"
  homepage "https://github.com/tarunprakash2468/private-index"
  version "0.2.0"
  license "MIT"

  depends_on :macos
  depends_on arch: :arm64

  url "https://github.com/tarunprakash2468/private-index/releases/download/v#{version}/private-index-cli-#{version}-darwin-arm64.tar.gz"
  sha256 "e999421bebd09ce51e65ce42917864ee2d2a744b2dd5d7c2374039304fd70f19"

  def install
    bin.install "private-index-cli" => "pi"
    bin.install_symlink bin/"pi" => "private-index"
    bin.install_symlink bin/"pi" => "private-index-cli"
  end

  test do
    assert_match "pi — Private Index", shell_output("#{bin}/pi help")
    assert_match "pi — Private Index", shell_output("#{bin}/private-index help")
  end
end
