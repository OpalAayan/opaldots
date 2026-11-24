#!/usr/bin/env bash

# Point Starship to your orange fruity theme
export STARSHIP_CONFIG="$HOME/.config/starship-fruity.toml"

# Launch Kitty with your custom class and config
exec kitty --class kitty-fruity --config "$HOME/.config/kitty/kitty-fruity.conf"
