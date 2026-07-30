# Commands to run in interactive sessions can go here
if status is-interactive
    # No greeting
    set fish_greeting

    # Use starship
    function starship_transient_prompt_func
        starship module character
    end
    if test "$TERM" != linux
        starship init fish | source
        enable_transience
    end

    # Colors
    # if test -f ~/.local/state/quickshell/user/generated/terminal/sequences.txt
    #     cat ~/.local/state/quickshell/user/generated/terminal/sequences.txt
    # end

    # ==============================================================================
    # PATH CONFIGURATION
    # ==============================================================================
    # Fish handles paths beautifully; you only need to add them once.
    fish_add_path ~/.npm-global/bin
    fish_add_path ~/.cargo/bin
    fish_add_path ~/.local/bin
    fish_add_path ~/go/bin
    #fish_add_path ~/.nix-profile/bin
    #fish_add_path ~/.opencode/bin
    #fish_add_path ~/.spicetify

    # ==============================================================================
    # JAVA SETUP (Java 26)
    # ==============================================================================
    #set -gx JAVA_HOME /usr/lib/jvm/java-26-openjdk
    #fish_add_path $JAVA_HOME/bin

    # JavaFX SDK
    #set -gx JAVAFX_HOME $HOME/.local/lib/javafx-sdk-24.0.1/lib
    #set -gx CLASSPATH $CLASSPATH $JAVAFX_HOME

    # ==============================================================================
    # GPU COMPATIBILITY FIXES
    # ==============================================================================
    # Gaslight Ghostty into thinking we have OpenGL 4.6 (Fixes Intel HD 4000 crash)
    #set -gx MESA_GL_VERSION_OVERRIDE 4.6
    #set -gx MESA_GLSL_VERSION_OVERRIDE 460

    # ==============================================================================
    # FZF INTEGRATION
    # ==============================================================================
    if type -q fzf
        fzf --fish | source
    end

    # ==============================================================================
    # ALIASES
    # ==============================================================================
    alias code='vscodium 2>/dev/null' # stfu      
    #alias bluej="~/.local/lib/bluej/bluej" # Manual BlueJ (its a java ide)
    alias rmpc="~/.config/rmpc/scripts/rmpc_music.sh" # RMPC Music

    # CMUS music dir (Wrapped in fish -c to isolate the directory change)
    alias cmus='fish -c "cd ~/Music && command cmus"'

    #alias boult="~/Tool~Scripting/reconnect_headset.sh" # Robust way for reconnecting (work on this )
    alias bt-battery="upower -e | grep 'headset' | xargs upower -i | grep 'percentage'"

    # Flappy (Wrapped in fish -c to isolate the directory change)
    #alias flappy=

    # A way to refresh mirrors
    # Manjaro
    #alias quicky="sudo pacman-mirrors --fasttrack 5" # quick mirrors fix
    #alias hardy="sudo pacman-mirrors --fasttrack 15" # takes time

    #Arch linux
    alias quicky="~/.local/bin/smart-mirrors.sh quick"
    alias hardy="~/.local/bin/smart-mirrors.sh hardy"

    # minecraft stuff
    #alias mcxx="cd ~/.local/share/PrismLauncher/instances/26.1.2/minecraft" # minecraft path
    #alias mcxy="nautilus ~/.local/share/PrismLauncher/instances/26.1.2/minecraft & disown" # minecraft path in GUI

    # waifuland stuff
    #alias huohuo="~/GitTest/waifuland/build/bin/waifuland --models_dir ~/.config/waifuland/profiles/huohuo_profile >/dev/null 2>&1"
    #alias alexia="~/GitTest/waifuland/build/bin/waifuland --models_dir ~/.config/waifuland/profiles/alexia_profile >/dev/null 2>&1"
    #alias changli="~/GitTest/waifuland/build/bin/waifuland --models_dir ~/.config/waifuland/profiles/changli_profile >/dev/null 2>&1"
    #alias waify="~/GitTest/waifuland/build/bin/waifuland --config ~/.config/waifuland/waify.json >/dev/null 2>&1 &"
    #alias wkill="pkill -9 -f waifuland"

    alias imv="kitty +kitten icat"
    alias psvk="pacman -Q | fzf --preview 'pacman -Qi {1}' --preview-window=right:60%"

    # kitty doesn't clear properly so we need to do this weird printing
    alias clear="printf '\033[2J\033[3J\033[1;1H'"
    alias celar="printf '\033[2J\033[3J\033[1;1H'"
    alias claer="printf '\033[2J\033[3J\033[1;1H'"

    alias ez="eza --icons"
    #alias n="nvim" #meh

    # Motocam overrides
    #alias motocam='scrcpy --video-source=camera --camera-facing=back --camera-size=1920x1440 --v4l2-sink=/dev/video10 --no-audio --no-window --video-codec=h264 --video-bit-rate=24M --max-fps=60'
    #alias motoplay='ffplay -f video4linux2 -input_format yuv420p -video_size 1920x1440 -fflags nobuffer -flags low_delay -framedrop -strict experimental -vf hflip -i /dev/video10'

    # ==============================================================================
    # FUNCTIONS
    # ==============================================================================
    function OsAge
        set pacman_log "/var/log/pacman.log"

        if not test -r "$pacman_log"
            echo " OS age: Unknown (cannot read $pacman_log)"
            return 1
        end

        set raw_date (head -n 1 "$pacman_log" | awk -F '[[]|[]]' '{print $2}')

        if test -z "$raw_date"
            echo " OS age: Unknown (no date found)"
            return 1
        end

        set install_epoch (date -d "$raw_date" +%s)
        set now_epoch (date +%s)
        set age_days (math "( $now_epoch - $install_epoch ) / 86400")
        set formatted_date (date -d "$raw_date" +"%b %d, %Y at %I:%M %p")

        echo "  OS age: $age_days days (since $formatted_date)"
    end
end
