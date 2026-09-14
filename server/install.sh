#!/usr/bin/env bash
# server-profile 一式をシステムへ配置する。dotfiles の移動で起動時適用が壊れないよう symlink ではなくコピーする
set -euo pipefail
cd "$(dirname "$0")"
sudo install -m 0755 server-profile /usr/local/sbin/server-profile
sudo install -d -m 0755 /etc/server-profiles
for p in profiles/*; do sudo install -m 0644 "$p" /etc/server-profiles/; done
sudo install -m 0644 systemd/server-profile.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable server-profile.service
echo "installed. apply with: sudo server-profile eco"
