# ~/.config/fish/config.fish

# ==============================================================================
# PATH CONFIGURATION (Runs for both interactive and non-interactive shells)
# ==============================================================================
fish_add_path ~/.npm-global/bin ~/.cargo/bin ~/.local/bin ~/go/bin
# fish_add_path ~/.nix-profile/bin ~/.opencode/bin ~/.spicetify

# JAVA SETUP (Uncomment when needed)
# set -gx JAVA_HOME /usr/lib/jvm/java-26-openjdk
# fish_add_path "$JAVA_HOME/bin"
# set -gx JAVAFX_HOME "$HOME/.local/lib/javafx-sdk-24.0.1/lib"
# set -gx CLASSPATH $CLASSPATH "$JAVAFX_HOME"

# GPU COMPATIBILITY FIXES (Uncomment when needed)
# set -gx MESA_GL_VERSION_OVERRIDE 4.6
# set -gx MESA_GLSL_VERSION_OVERRIDE 460

# ==============================================================================
# INTERACTIVE SESSION ONLY
# ==============================================================================
if status is-interactive
    # Disable welcome greeting
    set -g fish_greeting

    # Starship prompt (safe check so terminal never breaks if uninstalled)
    if type -q starship; and test "$TERM" != linux
        function starship_transient_prompt_func
            starship module character
        end
        starship init fish | source
        enable_transience
    end

    # Quickshell terminal color sequences (Uncomment if needed)
    # if test -f ~/.local/state/quickshell/user/generated/terminal/sequences.txt
    #     cat ~/.local/state/quickshell/user/generated/terminal/sequences.txt
    # end

    # FZF integration
    if type -q fzf
        fzf --fish | source
    end

    # ==============================================================================
    # ABBREVIATIONS (Expand live as you type, clean history, zero Enter-key bugs)
    # ==============================================================================
    # Safe replacement for the old ';s' keybinding
    abbr -a -- ';s' ls
    abbr -a -- celar clear
    abbr -a -- claer clear

    # ==============================================================================
    # ALIASES & WRAPPERS
    # ==============================================================================
    alias code='vscodium 2>/dev/null'
    alias rmpc="$HOME/.config/rmpc/scripts/rmpc_music.sh"
    alias cmus='fish -c "cd ~/Music && command cmus"'
    alias bt-battery="upower -e | grep 'headset' | xargs -r upower -i | grep 'percentage'"

    # Arch Linux mirror helpers
    alias quicky="$HOME/.local/bin/smart-mirrors.sh quick"
    alias hardy="$HOME/.local/bin/smart-mirrors.sh hardy"

    # Minecraft shortcuts
    alias mcxx="cd $HOME/.local/share/PrismLauncher/instances/26.3/minecraft"
    alias mcxy="nautilus $HOME/.local/share/PrismLauncher/instances/26.3/minecraft >/dev/null 2>&1 & disown"

    # Terminal & Pacman utilities
    alias imv="kitty +kitten icat"
    alias psvk="pacman -Q | fzf --preview 'pacman -Qi {1}' --preview-window=right:60%"
    alias ez="eza --icons"
    alias disptoggle="$HOME/.config/hypr/scripts/toggle-display.sh"
    alias kc="gcc -std=c89 -Wno-implicit-int -Wno-implicit-function-declaration"

    # Proper Kitty screen + scrollback clear
    function clear --description "Clear screen and scrollback buffer"
        printf '\033[2J\033[3J\033[1;1H'
    end

    # Commented-out extras (Uncomment when needed)
    # alias bluej="$HOME/.local/lib/bluej/bluej"
    # alias boult="$HOME/Tool~Scripting/reconnect_headset.sh"
    # alias n="nvim"
    # alias huohuo="$HOME/GitTest/waifuland/build/bin/waifuland --models_dir $HOME/.config/waifuland/profiles/huohuo_profile >/dev/null 2>&1"
    # alias alexia="$HOME/GitTest/waifuland/build/bin/waifuland --models_dir $HOME/.config/waifuland/profiles/alexia_profile >/dev/null 2>&1"
    # alias changli="$HOME/GitTest/waifuland/build/bin/waifuland --models_dir $HOME/.config/waifuland/profiles/changli_profile >/dev/null 2>&1"
    # alias waify="$HOME/GitTest/waifuland/build/bin/waifuland --config $HOME/.config/waifuland/waify.json >/dev/null 2>&1 & disown"
    # alias wkill="pkill -9 -f waifuland"
    # alias motocam='scrcpy --video-source=camera --camera-facing=back --camera-size=1920x1440 --v4l2-sink=/dev/video10 --no-audio --no-window --video-codec=h264 --video-bit-rate=24M --max-fps=60'
    # alias motoplay='ffplay -f video4linux2 -input_format yuv420p -video_size 1920x1440 -fflags nobuffer -flags low_delay -framedrop -strict experimental -vf hflip -i /dev/video10'

    # ==============================================================================
    # FUNCTIONS
    # ==============================================================================
    function OsAge --description "Show how many days ago Arch Linux was installed"
        set -l pacman_log "/var/log/pacman.log"

        if not test -r "$pacman_log"
            echo " OS age: Unknown (cannot read $pacman_log)"
            return 1
        end

        set -l raw_date (head -n 1 "$pacman_log" | string match -r '\[(.*?)\]' | tail -n 1)

        if test -z "$raw_date"
            echo " OS age: Unknown (no date found)"
            return 1
        end

        set -l install_epoch (date -d "$raw_date" +%s 2>/dev/null)
        if test -z "$install_epoch"
            echo " OS age: Unknown (failed to parse date)"
            return 1
        end

        set -l now_epoch (date +%s)
        set -l age_days (math -s0 "($now_epoch - $install_epoch) / 86400")
        set -l formatted_date (date -d "$raw_date" "+%Y-%m-%d")

        echo " OS age: $age_days days (installed $formatted_date)"
    end
end
