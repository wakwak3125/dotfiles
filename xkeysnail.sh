#!/bin/sh
# --device /dev/input/event8 'SteelSeries SteelSeries Apex M750 TKL'
if [ -x /usr/local/bin/xkeysnail ]; then
    xhost +SI:localuser:xkeysnail
    sudo -u xkeysnail DISPLAY=$DISPLAY /usr/local/bin/xkeysnail $HOME/dotfiles/config.py
fi

