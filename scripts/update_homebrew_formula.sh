#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# update_homebrew_formula.sh — Generate Formula/private-index.rb for Homebrew Tap
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-$(git describe --tags --always 2>/dev/null || echo "0.2.0")}"
VERSION="${VERSION#v}"

CLI_TARBALL="${REPO_ROOT}/dist/private-index-cli-${VERSION}-darwin-arm64.tar.gz"
SHA256="${2:-}"

if [[ -z "${SHA256}" ]]; then
    if [[ -f "${CLI_TARBALL}" ]]; then
        SHA256="$(shasum -a 256 "${CLI_TARBALL}" | awk '{print $1}')"
    else
        SHA256="PLACEHOLDER_SHA256"
    fi
fi

FORMULA_DIR="${REPO_ROOT}/Formula"
mkdir -p "${FORMULA_DIR}"
FORMULA_FILE="${FORMULA_DIR}/private-index.rb"

echo "==> Generating Homebrew formula: ${FORMULA_FILE} (Version: ${VERSION}, SHA256: ${SHA256})"

cat <<EOF > "${FORMULA_FILE}"
class PrivateIndex < Formula
  desc "Local, privacy-first semantic document indexing and search CLI (pi)"
  homepage "https://github.com/tarunprakash2468/private-index"
  version "${VERSION}"
  license "MIT"

  depends_on :macos
  depends_on arch: :arm64

  url "https://github.com/tarunprakash2468/private-index/releases/download/v#{version}/private-index-cli-#{version}-darwin-arm64.tar.gz"
  sha256 "${SHA256}"

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
    assert_match "pi — Private Index", shell_output("#{bin}/pi help")
    assert_match "pi — Private Index", shell_output("#{bin}/private-index help")
    assert_match "Private Index Database Statistics", shell_output("#{bin}/pi stats")
  end
end
EOF

# Also mirror into dist/ if dist exists
if [[ -d "${REPO_ROOT}/dist" ]]; then
    cp "${FORMULA_FILE}" "${REPO_ROOT}/dist/private-index.rb"
fi

echo "==> ✔ Formula generated successfully at ${FORMULA_FILE}"
