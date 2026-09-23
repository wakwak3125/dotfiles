#!/usr/bin/env bash
# 自宅サーバー用の設定一式をシステムへ配置する。dotfiles の移動で起動時適用が壊れないよう symlink ではなくコピーする
set -euo pipefail
cd "$(dirname "$0")"
sudo install -m 0755 server-profile /usr/local/sbin/server-profile
sudo install -m 0755 gui /usr/local/sbin/gui
sudo install -d -m 0755 /etc/server-profiles
for p in profiles/*; do sudo install -m 0644 "$p" /etc/server-profiles/; done
sudo install -m 0644 systemd/server-profile.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable server-profile.service

# GUI は gui on で必要なときだけ起動する。gdm3 を disable すると display-manager.service の
# symlink が消えて gui on で起動できなくなるため、既定の target だけを変える
sudo systemctl set-default multi-user.target

# Wayland の RustDesk はログイン画面を操作できないため自動ログインにする。GDM には drop-in の仕組みがないので custom.conf に追記する
GDM_CONF=/etc/gdm3/custom.conf
if ! sudo grep -q '^AutomaticLoginEnable *= *true' "$GDM_CONF"; then
  sudo sed -i "/^\[daemon\]/a AutomaticLoginEnable=true\nAutomaticLogin=$USER" "$GDM_CONF"
fi

echo "installed. apply with: sudo server-profile eco / start GUI with: sudo gui on"
