#!/bin/bash
# ====================================================================
#  vdiff — Visual Side-by-Side File Diff
#  v1.0.0 | Production-ready | Kitty/modern terminal optimized
# ====================================================================
set -u

readonly VERSION="1.0.0"
readonly PROG="$(basename "$0")"

# ── Default Options ──
OPT_LEFT=""
OPT_RIGHT=""
OPT_MODE="all"
OPT_MODE_SET=false
OPT_OUTPUT="z_extra_pkgs.txt"
OPT_SAVE=true
OPT_INTERACTIVE=true
OPT_CASE_INSENSITIVE=false
OPT_DEDUPE=false
OPT_NO_COLOR=false
OPT_DIM_RGB="70,70,90"
OPT_ADDED_RGB="119,221,119"
OPT_REMOVED_RGB="255,107,107"
readonly MIN_COLS=46

# Respect NO_COLOR convention (https://no-color.org/)
[[ -n "${NO_COLOR:-}" ]] && OPT_NO_COLOR=true

# ═══════════════════════════════════════
#  Color Initialisation
# ═══════════════════════════════════════
init_colors() {
    if $OPT_NO_COLOR; then
        RST="" BOLD="" DIM=""
        FG_R="" FG_G="" FG_Y="" FG_B="" FG_P="" FG_C="" FG_W="" FG_D="" FG_DD=""
        BG_R="" BG_G="" BG_H=""
        return
    fi
    RST=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
    local dr dg db ar ag ab rr rg rb
    IFS=',' read -r dr dg db <<< "$OPT_DIM_RGB"
    IFS=',' read -r ar ag ab <<< "$OPT_ADDED_RGB"
    IFS=',' read -r rr rg rb <<< "$OPT_REMOVED_RGB"
    FG_R=$'\033[38;2;'"${rr};${rg};${rb}m"
    FG_G=$'\033[38;2;'"${ar};${ag};${ab}m"
    FG_Y=$'\033[38;2;253;203;110m'
    FG_B=$'\033[38;2;116;185;255m'
    FG_P=$'\033[38;2;192;132;252m'
    FG_C=$'\033[38;2;129;230;217m'
    FG_W=$'\033[38;2;205;205;215m'
    FG_D=$'\033[38;2;'"${dr};${dg};${db}m"
    FG_DD=$'\033[38;2;'"$((dr>20?dr-20:0));$((dg>20?dg-20:0));$((db>20?db-20:0))m"
    BG_R=$'\033[48;2;50;15;22m'
    BG_G=$'\033[48;2;15;42;25m'
    BG_H=$'\033[48;2;30;30;48m'
}

# ═══════════════════════════════════════
#  Help / Usage
# ═══════════════════════════════════════
show_help() {
    cat <<EOF
${PROG} v${VERSION} — Visual side-by-side file diff

USAGE
  ${PROG} [OPTIONS] [FILE1] [FILE2]
  ${PROG}                                # interactive mode
  ${PROG} base.txt current.txt           # quick compare
  ${PROG} -l old.txt -r new.txt -m diff  # differences only

FILE OPTIONS
  -l, --left FILE          Left-side file
  -r, --right FILE         Right-side file

DISPLAY OPTIONS
  -m, --mode MODE          'all' (default) or 'diff' (differences only)
  -o, --output FILE        Save right-only lines to FILE
                           (default: z_extra_pkgs.txt)
      --no-save            Don't write an output file

COMPARISON OPTIONS
  -i, --case-insensitive   Case-insensitive comparison
      --dedupe             Remove duplicate lines before comparing

COLOR OPTIONS
      --dim R,G,B          Dim/shared-line text   (default: 70,70,90)
      --added R,G,B        Added-line text         (default: 119,221,119)
      --removed R,G,B      Removed-line text       (default: 255,107,107)
      --no-color           Disable all colors

OTHER
      --no-interactive     Skip prompts (requires -l and -r)
      --completion         Print bash completion script and exit
  -h, --help               Show this help
  -V, --version            Show version

ENVIRONMENT
  NO_COLOR    Set to any value to disable colors (no-color.org)

EXAMPLES
  ${PROG} --dim 100,100,140            # brighter dim text
  ${PROG} --no-color -l a -r b | cat   # pipe-friendly
  source <(./${PROG} --completion)     # enable bash tab-completion
EOF
    exit 0
}

# ═══════════════════════════════════════
#  Utility Helpers
# ═══════════════════════════════════════
_cols() { tput cols 2>/dev/null || echo "${COLUMNS:-80}"; }

strip_ansi() {
    # Remove ANSI SGR sequences; works with GNU & BSD sed
    printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g'
}

hline() {
    # Print $1 copies of $2 (default '─')
    local n="$1" ch="${2:-─}" i
    for ((i=0;i<n;i++)); do printf '%s' "$ch"; done
}

# Draw a self-sizing rounded box around arbitrary lines of text.
# Box width adapts to both content and terminal width.
draw_box() {
    local max_w=$(( $(_cols) - 4 ))
    (( max_w > 56 )) && max_w=56
    (( max_w < 24 )) && max_w=24
    local lines=("$@")

    # Measure widest line (stripped of ANSI)
    local widest=0
    for l in "${lines[@]}"; do
        local s; s="$(strip_ansi "$l")"
        (( ${#s} > widest )) && widest=${#s}
    done
    local inner=$(( widest + 2 ))
    (( inner > max_w )) && inner=$max_w

    local border; border="$(hline $inner)"
    printf "  %b╭%s╮%b\n" "$FG_C" "$border" "$RST"
    for l in "${lines[@]}"; do
        local s; s="$(strip_ansi "$l")"
        local pad=$(( inner - ${#s} - 2 ))
        (( pad < 0 )) && pad=0
        printf "  %b│%b %b%*s %b│%b\n" "$FG_C" "$RST" "$l" "$pad" "" "$FG_C" "$RST"
    done
    printf "  %b╰%s╯%b\n" "$FG_C" "$border" "$RST"
}

# Display file-pair statistics in a bordered table.
draw_stats() {
    local w=$(( $(_cols) - 4 ))
    (( w > 58 )) && w=58
    (( w < 36 )) && w=36
    local border; border="$(hline $w)"
    local inner=$(( w - 2 ))

    # Row helpers — compute plain-text length, then right-pad to inner width
    _row() {
        local plain="$1"; shift  # plain text for measuring
        local content="$*"       # ANSI-coloured content
        local pad=$(( inner - ${#plain} ))
        (( pad < 0 )) && pad=0
        printf "  %b│%b %b%*s %b│%b\n" \
            "$FG_D" "$RST" "$content" "$pad" "" "$FG_D" "$RST"
    }

    printf "  %b┌%s┐%b\n" "$FG_D" "$border" "$RST"

    local p1; p1=$(printf "◀ %-20s %5s lines" "$N1" "$F1_N")
    local c1; c1=$(printf "%b◀%b %b%-20s%b %b%5s%b %blines%b" \
        "$FG_R" "$RST" "${BOLD}${FG_W}" "$N1" "$RST" "$FG_P" "$F1_N" "$RST" "$FG_D" "$RST")
    _row "$p1" "$c1"

    local p2; p2=$(printf "▶ %-20s %5s lines" "$N2" "$F2_N")
    local c2; c2=$(printf "%b▶%b %b%-20s%b %b%5s%b %blines%b" \
        "$FG_G" "$RST" "${BOLD}${FG_W}" "$N2" "$RST" "$FG_P" "$F2_N" "$RST" "$FG_D" "$RST")
    _row "$p2" "$c2"

    printf "  %b├%s┤%b\n" "$FG_D" "$border" "$RST"

    local p3; p3=$(printf "Shared: %-5s  ◀ Removed: %-5s  ▶ Added: %-5s" \
        "$N_COMMON" "$N_LEFT" "$N_RIGHT")
    local c3; c3=$(printf "%bShared:%b %b%-5s%b  %b◀ Removed:%b %b%-5s%b  %b▶ Added:%b %b%-5s%b" \
        "$FG_D" "$RST" "$FG_W" "$N_COMMON" "$RST" \
        "$FG_R" "$RST" "$FG_W" "$N_LEFT"   "$RST" \
        "$FG_G" "$RST" "$FG_W" "$N_RIGHT"  "$RST")
    _row "$p3" "$c3"

    printf "  %b└%s┘%b\n" "$FG_D" "$border" "$RST"
}

# ═══════════════════════════════════════
#  Smart Read — Fish-style inline suggestions
# ═══════════════════════════════════════
#  ❯ Label: user_inp|ghost_suggestion
#  • Type to filter  • Tab to accept  • Enter to confirm  • Backspace to delete
_sr_suggestion=""        # current ghost suggestion (set by _sr_redraw)

smart_read() {
    local label="$1" default="$2"
    local input="" char=""
    _sr_suggestion=""

    # Prompt + initial ghost (default value)
    printf "  %b❯%b %b%s%b " "$FG_B" "$RST" "$FG_W" "$label" "$RST"
    printf "%b%s%b" "$FG_DD" "$default" "$RST"
    local dlen=${#default}
    (( dlen > 0 )) && printf '\033[%dD' "$dlen"

    while IFS= read -rs -n1 char; do
        case "$char" in
            '')                     # ── Enter ──
                [[ -z "$input" ]] && input="$default"
                printf '\r\033[2K'
                printf "  %b❯%b %b%s%b %b%s%b\n" \
                    "$FG_B" "$RST" "$FG_W" "$label" "$RST" "$FG_G" "$input" "$RST"
                break ;;
            $'\x7f'|$'\b')          # ── Backspace ──
                [[ -n "$input" ]] && input="${input%?}"
                _sr_redraw "$label" "$input" "$default" ;;
            $'\t')                  # ── Tab — accept suggestion ──
                if [[ -n "$_sr_suggestion" ]]; then
                    input="$_sr_suggestion"
                    [[ -d "$input" ]] && input="${input%/}/"
                fi
                _sr_redraw "$label" "$input" "$default" ;;
            $'\x1b')                # ── Escape seq — consume & skip ──
                read -rs -n1 -t 0.05 _ || true
                read -rs -n1 -t 0.05 _ || true ;;
            *)                      # ── Regular char ──
                input="${input}${char}"
                _sr_redraw "$label" "$input" "$default" ;;
        esac
    done
    SMART_REPLY="$input"
}

_sr_redraw() {
    local label="$1" current="$2" default="$3"
    printf '\r\033[2K'
    printf "  %b❯%b %b%s%b " "$FG_B" "$RST" "$FG_W" "$label" "$RST"
    _sr_suggestion=""

    if [[ -z "$current" ]]; then
        # Empty — show default as ghost
        printf "%b%s%b" "$FG_DD" "$default" "$RST"
        (( ${#default} > 0 )) && printf '\033[%dD' "${#default}"
    else
        # Find first file/dir matching prefix
        local match
        match="$(compgen -f -- "$current" 2>/dev/null | head -n1)"
        if [[ -n "$match" && "$match" != "$current" ]]; then
            _sr_suggestion="$match"
            local rest="${match#"$current"}"
            printf "%b%s%b%b%s%b" "$FG_W" "$current" "$RST" "$FG_DD" "$rest" "$RST"
            (( ${#rest} > 0 )) && printf '\033[%dD' "${#rest}"
        else
            printf "%b%s%b" "$FG_W" "$current" "$RST"
        fi
    fi
}

# ═══════════════════════════════════════
#  Argument Parsing
# ═══════════════════════════════════════
validate_rgb() {
    local val="$1" flag="$2" r g b
    IFS=',' read -r r g b <<< "$val"
    if [[ -z "${r:-}" || -z "${g:-}" || -z "${b:-}" ]]; then
        printf "Error: invalid colour for %s: '%s'. Use R,G,B (e.g. 70,70,90)\n" "$flag" "$val" >&2
        exit 1
    fi
    for v in "$r" "$g" "$b"; do
        if ! [[ "$v" =~ ^[0-9]+$ ]] || (( v > 255 )); then
            printf "Error: %s component '%s' out of range (0-255).\n" "$flag" "$v" >&2; exit 1
        fi
    done
}

parse_args() {
    local positional=()
    while (( $# )); do
        case "$1" in
            -l|--left)         OPT_LEFT="${2:?missing arg for $1}";  shift 2 ;;
            -r|--right)        OPT_RIGHT="${2:?missing arg for $1}"; shift 2 ;;
            -m|--mode)         OPT_MODE="${2:?missing arg for $1}";  OPT_MODE_SET=true; shift 2 ;;
            -o|--output)       OPT_OUTPUT="${2:?missing arg for $1}"; shift 2 ;;
            --no-save)         OPT_SAVE=false;             shift ;;
            -i|--case-insensitive) OPT_CASE_INSENSITIVE=true; shift ;;
            --dedupe)          OPT_DEDUPE=true;            shift ;;
            --no-interactive)  OPT_INTERACTIVE=false;      shift ;;
            --no-color)        OPT_NO_COLOR=true;          shift ;;
            --dim)             OPT_DIM_RGB="${2:?missing arg for $1}";     shift 2 ;;
            --added)           OPT_ADDED_RGB="${2:?missing arg for $1}";   shift 2 ;;
            --removed)         OPT_REMOVED_RGB="${2:?missing arg for $1}"; shift 2 ;;
            --completion)      emit_completion; exit 0 ;;
            -h|--help)         show_help ;;
            -V|--version)      echo "$PROG v$VERSION"; exit 0 ;;
            --)                shift; positional+=("$@"); break ;;
            -*)                printf "Unknown option: %s (try --help)\n" "$1" >&2; exit 1 ;;
            *)                 positional+=("$1"); shift ;;
        esac
    done
    # Positional fallback: FILE1 FILE2
    [[ ${#positional[@]} -ge 1 && -z "$OPT_LEFT"  ]] && OPT_LEFT="${positional[0]}"
    [[ ${#positional[@]} -ge 2 && -z "$OPT_RIGHT" ]] && OPT_RIGHT="${positional[1]}"
    # Validate mode
    case "$OPT_MODE" in all|diff) ;; *)
        printf "Invalid mode '%s'. Use 'all' or 'diff'.\n" "$OPT_MODE" >&2; exit 1 ;; esac
    validate_rgb "$OPT_DIM_RGB"     "--dim"
    validate_rgb "$OPT_ADDED_RGB"   "--added"
    validate_rgb "$OPT_REMOVED_RGB" "--removed"
}

# ═══════════════════════════════════════
#  File Validation & Preprocessing
# ═══════════════════════════════════════
validate_file() {
    local path="$1" label="$2"
    if [[ ! -e "$path" ]]; then
        printf "  %b✗ %s not found:%b %s\n" "$FG_R" "$label" "$RST" "$path" >&2; exit 1; fi
    if [[ ! -f "$path" ]]; then
        printf "  %b✗ %s is not a regular file:%b %s\n" "$FG_R" "$label" "$RST" "$path" >&2; exit 1; fi
    if [[ ! -r "$path" ]]; then
        printf "  %b✗ %s permission denied:%b %s\n" "$FG_R" "$label" "$RST" "$path" >&2; exit 1; fi
    # Binary check via mime type
    if command -v file &>/dev/null; then
        local mime; mime=$(file --mime-type -b "$path" 2>/dev/null || echo "text/plain")
        if [[ "$mime" != text/* && "$mime" != application/json && "$mime" != application/xml \
           && "$mime" != application/x-empty && "$mime" != inode/x-empty ]]; then
            printf "  %b⚠ %s looks binary (%s):%b %s\n" "$FG_Y" "$label" "$mime" "$RST" "$path" >&2; exit 1; fi
    fi
}

# Sort/dedupe/normalise a file into a temp copy; prints the temp path.
prepare_file() {
    local src="$1"
    local tmp; tmp=$(mktemp)
    # Strip carriage returns (Windows / mixed line endings)
    tr -d '\r' < "$src" |
        # Optional: lowercase for case-insensitive compare
        { $OPT_CASE_INSENSITIVE && tr '[:upper:]' '[:lower:]' || cat; } > "$tmp"

    if $OPT_DEDUPE; then
        sort -u -o "$tmp" "$tmp"
    else
        sort -o "$tmp" "$tmp"
    fi
    printf '%s' "$tmp"
}

# ═══════════════════════════════════════
#  Diff Generation
# ═══════════════════════════════════════
generate_diff() {
    local mode="$1" lf="$2" rf="$3"
    local cols half border
    cols=$(_cols)
    half=$(( (cols - 3) / 2 ))
    (( half < 12 )) && half=12
    border="$(hline "$half")"

    local show_common=1
    [[ "$mode" == "diff" ]] && show_common=0

    # ╭── top ──╮
    printf "%b╭%s─┬─%s╮%b\n" "$FG_D" "$border" "$border" "$RST"

    # Column headers
    local lh rh
    lh=$(printf " ◀  %-$((half-5))s" "$N1")
    rh=$(printf " ▶  %-$((half-5))s" "$N2")
    printf "%b%b%s%b %b│%b %b%b%s%b\n" \
        "$BG_H" "${BOLD}${FG_R}" "$lh" "$RST${BG_H}" "${FG_D}" "$RST" \
        "$BG_H" "${BOLD}${FG_G}" "$rh" "$RST"

    # ├── sep ──┤
    printf "%b├%s─┼─%s┤%b\n" "$FG_D" "$border" "$border" "$RST"

    # Content
    comm "$lf" "$rf" | awk \
        -v half="$half" \
        -v show="$show_common" \
        -v rst="$RST" \
        -v fg_r="$FG_R"  -v fg_g="$FG_G" \
        -v fg_d="$FG_D"  -v fg_dd="$FG_DD" \
        -v bg_r="$BG_R"  -v bg_g="$BG_G" \
    '{
        line = $0
        if (substr(line,1,2) == "\t\t") {
            if (!show) next
            pkg = substr(line,3)
            L = sprintf(" %-" (half-1) "s", pkg); L = substr(L,1,half)
            R = L
            printf "%s%s%s %s│%s %s%s%s\n", fg_dd, L, rst, fg_dd, rst, fg_dd, R, rst
        } else if (substr(line,1,1) == "\t") {
            pkg = substr(line,2)
            L = sprintf("%-" half "s", "");        L = substr(L,1,half)
            R = sprintf(" %-" (half-1) "s", pkg);  R = substr(R,1,half)
            printf "%s %s►%s %s%s%s%s\n", L, fg_g, rst, bg_g, fg_g, R, rst
        } else {
            pkg = line
            L = sprintf(" %-" (half-1) "s", pkg);  L = substr(L,1,half)
            R = sprintf("%-" half "s", "");         R = substr(R,1,half)
            printf "%s%s%s %s◄%s %s\n", bg_r, fg_r, L, rst fg_r, rst, R
        }
    }'

    # ╰── bottom ──╯
    printf "%b╰%s─┴─%s╯%b\n" "$FG_D" "$border" "$border" "$RST"
    echo ""
    printf "  %b━━ ◀ Removed: %s%b    %b━━ ▶ Added: %s%b    %b━━ Shared: %s%b\n" \
        "$FG_R" "$N_LEFT" "$RST" "$FG_G" "$N_RIGHT" "$RST" "$FG_D" "$N_COMMON" "$RST"
    echo ""
}

# ═══════════════════════════════════════
#  Bash Completion Script
# ═══════════════════════════════════════
emit_completion() {
    cat <<'COMP'
# bash completion for compare_pkgs.sh / vdiff
# Activate:  source <(./compare_pkgs.sh --completion)
_vdiff_comp() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="-l --left -r --right -m --mode -o --output
          -i --case-insensitive --dedupe --no-save
          --no-interactive --no-color --dim --added --removed
          --completion -h --help -V --version"
    case "$prev" in
        -l|--left|-r|--right|-o|--output) COMPREPLY=($(compgen -f -- "$cur")); return;;
        -m|--mode)    COMPREPLY=($(compgen -W "all diff" -- "$cur")); return;;
        --dim|--added|--removed)
            COMPREPLY=($(compgen -W "70,70,90 100,100,130 119,221,119 255,107,107 200,200,220" -- "$cur")); return;;
    esac
    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "$opts" -- "$cur"))
    else
        COMPREPLY=($(compgen -f -- "$cur"))
    fi
}
complete -o filenames -F _vdiff_comp compare_pkgs.sh vdiff
COMP
}

# ═══════════════════════════════════════
#  Main
# ═══════════════════════════════════════
main() {
    parse_args "$@"
    init_colors

    # ── Terminal width guard ──
    local cols; cols=$(_cols)
    if (( cols < MIN_COLS )); then
        printf "%b⚠ Terminal too narrow (%d cols, need %d).%b\n" "$FG_Y" "$cols" "$MIN_COLS" "$RST" >&2
        exit 1
    fi

    # ── Banner ──
    $OPT_INTERACTIVE && clear
    echo ""
    draw_box \
        "${BOLD}${FG_P}◈  Visual File Diff${RST}" \
        "${FG_D}Side-by-side comparison${RST}  ${FG_DD}v${VERSION}${RST}"
    echo ""

    # ── Collect file paths ──
    if $OPT_INTERACTIVE; then
        [[ -z "$OPT_LEFT"  ]] && { smart_read "File 1 (left):" "xbase.txt";  OPT_LEFT="$SMART_REPLY"; }
        [[ -z "$OPT_RIGHT" ]] && { smart_read "File 2 (right):" "ybase.txt"; OPT_RIGHT="$SMART_REPLY"; }
        echo ""
    else
        if [[ -z "$OPT_LEFT" || -z "$OPT_RIGHT" ]]; then
            echo "Error: --no-interactive requires -l/--left and -r/--right." >&2; exit 1
        fi
    fi

    # ── Validate ──
    validate_file "$OPT_LEFT"  "File 1"
    validate_file "$OPT_RIGHT" "File 2"

    # Self-compare guard
    local rp_l rp_r
    rp_l=$(realpath "$OPT_LEFT" 2>/dev/null  || echo "$OPT_LEFT")
    rp_r=$(realpath "$OPT_RIGHT" 2>/dev/null || echo "$OPT_RIGHT")
    if [[ "$rp_l" == "$rp_r" ]]; then
        printf "  %b⚠ Both paths resolve to the same file — nothing to diff.%b\n" "$FG_Y" "$RST"
        exit 0
    fi

    # ── Preprocess ──
    local prep_l prep_r
    prep_l=$(prepare_file "$OPT_LEFT")
    prep_r=$(prepare_file "$OPT_RIGHT")
    trap 'rm -f "$prep_l" "$prep_r"' EXIT INT TERM

    # ── Warnings ──
    [[ ! -s "$prep_l" ]] && printf "  %b⚠ File 1 is empty.%b\n" "$FG_Y" "$RST"
    [[ ! -s "$prep_r" ]] && printf "  %b⚠ File 2 is empty.%b\n" "$FG_Y" "$RST"
    local l1 l2
    l1=$(wc -l < "$prep_l" | tr -d ' '); l2=$(wc -l < "$prep_r" | tr -d ' ')
    if (( l1 > 10000 || l2 > 10000 )); then
        printf "  %b⚠ Large files (%s + %s lines) — may be slow.%b\n" "$FG_Y" "$l1" "$l2" "$RST"
    fi

    # ── Statistics ──
    N1="$(basename "$OPT_LEFT")"
    N2="$(basename "$OPT_RIGHT")"
    F1_N="$l1"; F2_N="$l2"
    N_COMMON=$(comm -12 "$prep_l" "$prep_r" | wc -l | tr -d ' ')
    N_LEFT=$(comm -23 "$prep_l" "$prep_r"   | wc -l | tr -d ' ')
    N_RIGHT=$(comm -13 "$prep_l" "$prep_r"  | wc -l | tr -d ' ')

    draw_stats
    echo ""

    # ── Save extras ──
    if $OPT_SAVE; then
        comm -13 "$prep_l" "$prep_r" > "$OPT_OUTPUT"
        printf "  %b✓%b %bExtras saved to:%b %b%s%b %b(%s entries)%b\n" \
            "$FG_G" "$RST" "$FG_W" "$RST" "$FG_G" "$OPT_OUTPUT" "$RST" "$FG_D" "$N_RIGHT" "$RST"
        echo ""
    fi

    # ── Identical? ──
    if (( N_LEFT == 0 && N_RIGHT == 0 )); then
        printf "  %b✓ Files are identical — nothing to diff.%b\n" "$FG_G" "$RST"
        exit 0
    fi

    # ── View mode prompt (interactive only, unless already set) ──
    local view_mode="$OPT_MODE"
    if $OPT_INTERACTIVE && ! $OPT_MODE_SET; then
        printf "  %bView mode:%b\n" "$FG_W" "$RST"
        printf "    %b1%b%b)%b %bAll lines%b          %b(shared dimmed)%b\n"   "$FG_B" "$RST" "$FG_D" "$RST" "$FG_W" "$RST" "$FG_D" "$RST"
        printf "    %b2%b%b)%b %bDifferences only%b   %b(hide shared)%b\n"    "$FG_B" "$RST" "$FG_D" "$RST" "$FG_W" "$RST" "$FG_D" "$RST"
        echo ""
        local mc
        read -e -p "$(printf "  %b❯%b %bChoose %b[1]%b:%b " "$FG_B" "$RST" "$FG_W" "$FG_D" "$FG_W" "$RST")" mc
        [[ "${mc:-1}" == "2" ]] && view_mode="diff"
        echo ""
    fi

    printf "  %bLaunching viewer … %bq%b to exit, arrows to scroll%b\n" \
        "$FG_D" "$FG_W" "$FG_D" "$RST"

    generate_diff "$view_mode" "$prep_l" "$prep_r" | less -RS
}

main "$@"
