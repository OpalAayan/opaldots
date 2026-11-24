#!/bin/sh
if [ -f "$HOME/.config/kitty/nmtui-theme.conf" ]; then
  exec kitty --class nmtui-floating \
    --config "$HOME/.config/kitty/nmtui-theme.conf" \
    -e nmtui
else
  exec kitty --class nmtui-floating -e nmtui
fi
