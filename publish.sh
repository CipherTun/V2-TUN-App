#!/usr/bin/env bash
# Creates the public repo CipherTun/V2-TUN-App with description and topics, then pushes this folder.
# Needs the GitHub CLI (gh) logged in as CipherTun: `gh auth login`.
set -euo pipefail
cd "$(dirname "$0")"

REPO="CipherTun/V2-TUN-App"
DESC="V2-TUN: a Flutter + Kotlin Android client for the io.surprise.vpn tunnel library. TUN and SOCKS5 modes, subscriptions, split tunneling, per-app VPN, payload tools."
TOPICS=(flutter dart kotlin android vpn vpn-client proxy tun tunnel socks5 vless vmess trojan shadowsocks hysteria2 ssh split-tunneling material-design gomobile)

[ -d .git ] || git init -b main
git add -A
git commit -m "Initial commit: V2-TUN app" || true

gh repo create "$REPO" --public --description "$DESC" --source=. --remote=origin --push
args=()
for t in "${TOPICS[@]}"; do args+=(--add-topic "$t"); done
gh repo edit "$REPO" "${args[@]}"
echo "Published: https://github.com/$REPO"
