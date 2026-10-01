#!/usr/bin/env bash
set -euo pipefail
backend_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$HOME/.cargo/bin:$PATH"
export CARGO_TARGET_DIR="$HOME/.cache/mikky-daemon-target"
cargo build --release --locked --manifest-path "$backend_dir/Cargo.toml"
mkdir -p "$backend_dir/target/linux-release"
cp "$CARGO_TARGET_DIR/release/mikkyd" "$backend_dir/target/linux-release/mikkyd-linux.new"
mv -f "$backend_dir/target/linux-release/mikkyd-linux.new" "$backend_dir/target/linux-release/mikkyd-linux"
