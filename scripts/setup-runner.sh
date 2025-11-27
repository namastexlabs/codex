#!/bin/bash
# Setup GitHub Actions self-hosted runner for codex
# Run this inside your Proxmox LXC container
set -euo pipefail

RUNNER_VERSION="${RUNNER_VERSION:-2.322.0}"
RUNNER_DIR="${RUNNER_DIR:-/opt/actions-runner}"
RUST_VERSION="${RUST_VERSION:-1.90}"

echo "=== Codex CI/CD Runner Setup ==="
echo "Runner version: $RUNNER_VERSION"
echo "Rust version: $RUST_VERSION"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (for apt install)"
   exit 1
fi

echo "=== Installing system dependencies ==="
apt update
apt install -y \
  curl wget git \
  build-essential pkg-config \
  libssl-dev musl-tools \
  python3 python3-pip \
  jq tar gzip zip unzip

echo "=== Installing Rust ==="
if command -v rustup &> /dev/null; then
    echo "Rust already installed, updating..."
    rustup update
else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain "$RUST_VERSION"
fi

# Source cargo env
export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
export PATH="$CARGO_HOME/bin:$PATH"
source "$CARGO_HOME/env" 2>/dev/null || true

echo "=== Setting up Rust toolchain ==="
rustup default "$RUST_VERSION"
rustup component add rustfmt clippy

# Add cross-compilation targets
echo "=== Adding cross-compilation targets ==="
rustup target add x86_64-unknown-linux-gnu
rustup target add x86_64-unknown-linux-musl
rustup target add aarch64-unknown-linux-gnu
rustup target add aarch64-unknown-linux-musl

echo "=== Installing cargo-zigbuild for ARM cross-compilation ==="
pip3 install ziglang --break-system-packages 2>/dev/null || pip3 install ziglang
cargo install cargo-zigbuild --locked

echo "=== Installing additional cargo tools ==="
cargo install cargo-nextest --locked  # Fast test runner
cargo install sccache --locked        # Compilation cache

echo "=== Setting up GitHub Actions runner ==="
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

# Download runner
RUNNER_ARCH="x64"
if [[ $(uname -m) == "aarch64" ]]; then
    RUNNER_ARCH="arm64"
fi

RUNNER_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
echo "Downloading runner from: $RUNNER_URL"
curl -o actions-runner.tar.gz -L "$RUNNER_URL"
tar xzf actions-runner.tar.gz
rm actions-runner.tar.gz

echo "=== Creating persistent cache directories ==="
mkdir -p /opt/cargo-home /opt/sccache
chmod 755 /opt/cargo-home /opt/sccache

echo "=== Creating runner environment file ==="
cat > "$RUNNER_DIR/.env" << 'EOF'
# Cargo configuration
CARGO_HOME=/opt/cargo-home
CARGO_INCREMENTAL=1

# sccache configuration
SCCACHE_DIR=/opt/sccache
SCCACHE_CACHE_SIZE=20G
RUSTC_WRAPPER=sccache

# Rust configuration
RUST_BACKTRACE=1
CARGO_TERM_COLOR=always
EOF

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "Next steps:"
echo ""
echo "1. Get a runner registration token from GitHub:"
echo "   https://github.com/namastexlabs/codex/settings/actions/runners/new"
echo ""
echo "2. Configure the runner (run as non-root user):"
echo "   cd $RUNNER_DIR"
echo "   ./config.sh --url https://github.com/namastexlabs/codex \\"
echo "               --token <YOUR_TOKEN> \\"
echo "               --labels self-hosted,Linux,X64,codex \\"
echo "               --name codex-builder \\"
echo "               --work /opt/actions-runner/_work"
echo ""
echo "3. Install and start the runner service:"
echo "   sudo ./svc.sh install"
echo "   sudo ./svc.sh start"
echo ""
echo "4. Verify the runner appears in GitHub:"
echo "   https://github.com/namastexlabs/codex/settings/actions/runners"
echo ""
