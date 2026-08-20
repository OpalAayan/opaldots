#!/bin/bash
#
# ╭─────────────────────────────────────────────────────────╮
# │      🥧✨ ~(˘▾˘~) HYPR-BAKERY v4.0 (~˘▾˘)~ ✨🥧         │
# │                  ~ Universal Edition ~                  │
# │                                                         │
# │  The Swiss Army Knife for Wallpapers! Made with 💖      │
# │  • Still Images (Resize, crop, optimize)                │
# │  • Live Wallpapers (Video → WebP/GIF/MP4)               │
# ╰─────────────────────────────────────────────────────────╯
#

set -uo pipefail

# ==================== CONSTANTS ====================
readonly VERSION="4.0"
readonly EDITION="Universal Edition"
readonly SCRIPT_NAME="$(basename "$0")"
readonly CPU_THREADS="$(nproc 2>/dev/null || echo 4)"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly DIM='\033[2m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Resolution presets
declare -A PRESETS=(
  ["0"]="auto|Auto-Detect Screen"
  ["1"]="1920x1080|Full HD (1080p)"
  ["2"]="2560x1440|Quad HD (2K)"
  ["3"]="3840x2160|Ultra HD (4K)"
  ["4"]="1366x768|HD (768p)"
  ["5"]="1280x720|HD (720p)"
  ["6"]="custom|Custom Resolution"
)

# FPS presets
declare -A FPS_PRESETS=(
  ["1"]="15|Low-Spec / Battery Saver"
  ["2"]="24|Cinematic (Film-like)"
  ["3"]="30|Balanced (Recommended)"
  ["4"]="60|High-Performance"
  ["5"]="custom|Custom FPS"
)

# Quality presets
declare -A QUALITY_PRESETS=(
  ["1"]="high|High Quality (CRF 18) — Big files, looks perfect"
  ["2"]="balanced|Balanced (CRF 23) — Best for general use ⭐"
  ["3"]="potato|Potato Mode (CRF 28) — Tiny files, lowest CPU"
)

# Junk prefixes to clean from filenames
readonly JUNK_PREFIXES=("unsplash-" "pexels-" "wallhaven-" "pixabay-" "freepik-")

# ==================== GLOBAL STATE ====================
SOURCE_DIR=""
OUTPUT_DIR=""
TARGET_RES=""
WIDTH=""
HEIGHT=""
PREVIEW_MODE=false
INTERACTIVE_MODE=true
CONFLICT_MODE="merge"  # merge, wipe, backup
RENAME_MODE="original" # original, sequential, random

# Scope mode (new in v4.0)
SCOPE_MODE=""            # "bundle" or "single"
SINGLE_INPUT_FILE=""     # path for single-file mode
SINGLE_SAVE_MODE=""      # "saveas" or "replace"

# Video-specific globals
BAKE_MODE="" # images, videos
VIDEO_INPUT_EXT="mp4"
VIDEO_OUTPUT_FORMAT="webp" # webp, gif, mp4
VIDEO_DURATION="10"        # full, 10, 30
VIDEO_FPS=30               # Dynamic, not hardcoded
VIDEO_QUALITY="balanced"   # high, balanced, potato
VIDEO_CRF=23               # Derived from quality
WEBP_QUALITY=75            # Derived from quality

# Counters
declare -i count_processed=0 count_skipped=0 count_gifs=0 count_errors=0 count_total=0
declare -i total_pixels=0 original_size_bytes=0 output_size_bytes=0

# ==================== LOGGING FUNCTIONS ====================
log_info() { echo -e "${CYAN}💬${NC} $1"; }
log_ok() { echo -e "${GREEN}✨${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠️${NC}  $1"; }
log_err() { echo -e "${RED}💥${NC} $1" >&2; }
log_skip() { echo -e "${DIM}⏭️${NC}  $1"; }
log_fix() { echo -e "${MAGENTA}🔧${NC} $1"; }
log_gif() { echo -e "${BLUE}👾${NC} $1"; }
log_img() { echo -e "${GREEN}🖼️${NC}  $1"; }
log_vid() { echo -e "${MAGENTA}🎬${NC} $1"; }

# ==================== UTILITY FUNCTIONS ====================
show_banner() {
  # Box: col 1 = left border, cols 2-58 = content, col 59 = right border
  local rc='\033[59G'  # ANSI: move cursor to column 59 (right border)
  local box_w=57
  local border_line
  border_line=$(printf '─%.0s' $(seq 1 $box_w))
  local empty_line
  printf -v empty_line "%-${box_w}s" ""

  echo ""
  echo -e "${MAGENTA}╭${border_line}╮${NC}"
  echo -e "${MAGENTA}│${NC}${empty_line}${MAGENTA}│${NC}"
  echo -e "${MAGENTA}│${NC}       ${WHITE}🥧✨${NC} ${CYAN}~(˘▾˘~)${NC} HYPR-BAKERY v${VERSION} ${CYAN}(~˘▾˘)~${NC} ${WHITE}✨🥧${NC}${rc}${MAGENTA}│${NC}"
  echo -e "${MAGENTA}│${NC}                 ${DIM}~ ${EDITION} ~${NC}${rc}${MAGENTA}│${NC}"
  echo -e "${MAGENTA}│${NC}${empty_line}${MAGENTA}│${NC}"
  echo -e "${MAGENTA}│${NC}   ${DIM}The Swiss Army Knife for Wallpapers! Made with 💖${NC}${rc}${MAGENTA}│${NC}"
  echo -e "${MAGENTA}│${NC}${empty_line}${MAGENTA}│${NC}"
  echo -e "${MAGENTA}╰${border_line}╯${NC}"
  echo ""
}

show_help() {
  echo -e "${BOLD}USAGE:${NC}"
  echo -e "    $SCRIPT_NAME [OPTIONS]"
  echo -e "    $SCRIPT_NAME --source <dir> --output <dir> --res <WxH> --mode <images|videos>"
  echo -e "    $SCRIPT_NAME --single <file> --res <WxH> [--save-mode saveas|replace]"
  echo ""
  echo -e "${BOLD}OPTIONS:${NC}"
  echo -e "    ${CYAN}-s, --source${NC} <dir>        Source directory (default: \$PWD)"
  echo -e "    ${CYAN}-o, --output${NC} <dir>        Output directory (default: \$PWD/baked)"
  echo -e "    ${CYAN}-r, --res${NC} <WxH>           Target resolution (e.g., 1920x1080)"
  echo -e "    ${CYAN}-m, --mode${NC} <type>         Mode: images or videos"
  echo -e "    ${CYAN}-p, --preview${NC}             Preview mode (dry run)"
  echo -e "    ${CYAN}--conflict${NC} <mode>         Conflict handling: merge|wipe|backup"
  echo -e "    ${CYAN}--rename${NC} <mode>           Rename mode: original|sequential|random"
  echo ""
  echo -e "${BOLD}SINGLE-FILE OPTIONS:${NC}"
  echo -e "    ${CYAN}--single${NC} <file>           Process a single image or video"
  echo -e "    ${CYAN}--save-mode${NC} <mode>        Save mode: saveas|replace (default: saveas)"
  echo ""
  echo -e "${BOLD}VIDEO OPTIONS:${NC}"
  echo -e "    ${CYAN}--input-ext${NC} <ext>         Input video extension (default: mp4)"
  echo -e "    ${CYAN}--format${NC} <fmt>            Output: webp|gif|mp4 (default: webp)"
  echo -e "    ${CYAN}--duration${NC} <sec>          Trim to: full|10|30 seconds"
  echo -e "    ${CYAN}--fps${NC} <num>               Output FPS (15/24/30/60 or custom)"
  echo -e "    ${CYAN}--quality${NC} <level>         Quality: high|balanced|potato"
  echo ""
  echo -e "${BOLD}SYSTEM INFO:${NC}"
  echo -e "    ${DIM}CPU Threads detected:${NC} ${WHITE}$CPU_THREADS${NC}"
  echo ""
  echo -e "${BOLD}EXAMPLES:${NC}"
  echo -e "    ${DIM}# Interactive mode${NC}"
  echo -e "    $SCRIPT_NAME"
  echo ""
  echo -e "    ${DIM}# Quick single-file resize${NC}"
  echo -e "    $SCRIPT_NAME --single ~/wallpaper.jpg --res 1920x1080"
  echo ""
  echo -e "    ${DIM}# Single file, replace original${NC}"
  echo -e "    $SCRIPT_NAME --single ~/wall.png --res 2560x1440 --save-mode replace"
  echo ""
  echo -e "    ${DIM}# Resize images from current directory${NC}"
  echo -e "    $SCRIPT_NAME -s . -o ./out -r 1920x1080 -m images"
  echo ""
  echo -e "    ${DIM}# Convert videos to animated WebP for swww${NC}"
  echo -e "    $SCRIPT_NAME -s ~/Videos -o ~/Live -r 1366x768 -m videos --format webp --fps 30"
  echo ""
  echo -e "    ${DIM}# Potato quality for old laptops${NC}"
  echo -e "    $SCRIPT_NAME -s . -o ./out -m videos --quality potato --fps 15"
}

show_version() {
  echo -e "🥧 $SCRIPT_NAME v$VERSION — $EDITION"
  echo -e "   ${DIM}CPU Threads: $CPU_THREADS${NC}"
}

check_dependencies() {
  local missing=()
  for cmd in ffmpeg ffprobe; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_err "Missing required tools: ${missing[*]}"
    echo ""
    echo -e "    ${DIM}Install with:${NC}"
    echo -e "    ${CYAN}sudo pacman -S ffmpeg${NC}    ${DIM}(Arch)${NC}"
    echo -e "    ${CYAN}sudo apt install ffmpeg${NC}  ${DIM}(Debian/Ubuntu)${NC}"
    echo -e "    ${CYAN}sudo dnf install ffmpeg${NC}  ${DIM}(Fedora)${NC}"
    exit 1
  fi
}

validate_resolution() {
  local res="$1"
  if [[ ! "$res" =~ ^[0-9]+x[0-9]+$ ]]; then
    log_err "Invalid resolution format: $res"
    echo -e "    ${DIM}Expected: WIDTHxHEIGHT (e.g., 1920x1080)${NC}"
    return 1
  fi
  return 0
}

validate_directory() {
  local dir="$1"
  local type="$2"

  if [[ -z "$dir" ]]; then
    log_err "Directory path cannot be empty"
    return 1
  fi

  dir="${dir/#\~/$HOME}"

  if [[ "$type" == "source" ]]; then
    if [[ ! -d "$dir" ]]; then
      log_err "Source directory does not exist: $dir"
      return 1
    fi
  elif [[ "$type" == "output" ]]; then
    if [[ ! -d "$dir" ]]; then
      echo -e "${YELLOW}Output directory doesn't exist.${NC}"
      read -rp "Create it? [Y/n]: " create_choice
      if [[ "${create_choice,,}" != "n" ]]; then
        mkdir -p "$dir" && log_ok "Created: $dir" || {
          log_err "Failed to create"
          return 1
        }
      else
        return 1
      fi
    fi
  fi
  return 0
}

clean_filename() {
  local name="$1"
  local cleaned="$name"
  for prefix in "${JUNK_PREFIXES[@]}"; do
    cleaned="${cleaned#$prefix}"
  done
  cleaned="${cleaned#_}"
  cleaned="${cleaned%_}"
  echo "$cleaned"
}

get_display_name() {
  local name="$1"
  echo "${name//_/ }" | sed 's/-/ /g'
}

cleanup() {
  local staging_dir="$OUTPUT_DIR/.bakery_staging"
  if [[ -n "$staging_dir" && "$staging_dir" == *"/.bakery_staging" && -d "$staging_dir" ]]; then
    rm -rf "$staging_dir"
  fi
}

generate_random_id() {
  # Pure bash — 6 hex chars (~16M combos, no xxd/vim dep)
  printf '%04x%02x' "$RANDOM" $(( RANDOM % 256 ))
}

# ==================== HISTORY MANAGEMENT ====================
readonly BAKERY_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hyprbakery"
readonly BAKERY_HISTORY_FILE="$BAKERY_CACHE_DIR/path_history"

_history_load() {
  local -n _arr=$1
  _arr=()
  if [[ -f "$BAKERY_HISTORY_FILE" ]]; then
    mapfile -t _arr < "$BAKERY_HISTORY_FILE"
  fi
}

_history_save() {
  local entry="$1"
  [[ -z "$entry" ]] && return
  mkdir -p "$BAKERY_CACHE_DIR"
  { grep -vxF "$entry" "$BAKERY_HISTORY_FILE" 2>/dev/null || true; echo "$entry"; } | tail -100 > "${BAKERY_HISTORY_FILE}.tmp"
  mv "${BAKERY_HISTORY_FILE}.tmp" "$BAKERY_HISTORY_FILE"
}

_history_match() {
  local prefix="$1"
  local -n _entries=$2
  [[ -z "$prefix" ]] && return 1
  local i
  for (( i=${#_entries[@]}-1; i>=0; i-- )); do
    if [[ "${_entries[i]}" == "$prefix"* && "${_entries[i]}" != "$prefix" ]]; then
      echo "${_entries[i]}"
      return 0
    fi
  done
  return 1
}

# ==================== TAB COMPLETION ====================
_rl_tab_complete() {
  local input="$1"
  local expanded="${input/#\~/$HOME}"

  [[ -z "$expanded" ]] && expanded="./"

  local -a matches
  mapfile -t matches < <(compgen -f -- "$expanded" 2>/dev/null)

  if [[ ${#matches[@]} -eq 0 ]]; then
    return 1
  fi

  if [[ ${#matches[@]} -eq 1 ]]; then
    local result="${matches[0]}"
    [[ "$input" == "~"* ]] && result="~${result#$HOME}"
    [[ -d "${matches[0]}" ]] && result="${result%/}/"
    echo "$result"
    return 0
  fi

  # Multiple matches: find longest common prefix
  local common="${matches[0]}"
  local m
  for m in "${matches[@]}"; do
    while [[ ${#common} -gt 0 && "${m:0:${#common}}" != "$common" ]]; do
      common="${common:0:${#common}-1}"
    done
  done

  [[ "$input" == "~"* ]] && common="~${common#$HOME}"

  # Show available matches below the input line (to /dev/tty so it
  # doesn't pollute the captured stdout return value)
  {
    printf '\n'
    local count=0 base
    for m in "${matches[@]}"; do
      base=$(basename "$m")
      [[ -d "$m" ]] && base+="/"
      printf '  \033[2m%s\033[0m' "$base"
      ((count++))
      if [[ $count -ge 6 ]]; then
        printf '  \033[2m...(+%d more)\033[0m' $(( ${#matches[@]} - count ))
        break
      fi
    done
    printf '\n'
  } > /dev/tty

  echo "$common"
  return 2  # 2 = multiple matches shown
}

# ==================== READLINE INPUT ====================
# readline_input <prompt> [default] [use_history] [use_completion]
#
# A tiny readline replacement that gives you:
#   Backspace, Left/Right, Home/End, Delete, Ctrl+A/E/U/W
#   Fish-style ghost-text autosuggestion from path_history
#   Tab-completion for filesystem paths
#
# Returns the entered text in $REPLY.

_rl_render() {
  local prompt="$1" buffer="$2" cursor="$3" suggestion="$4"

  # Clear current line
  printf '\r\033[K'

  # Print prompt + buffer
  printf '%s%s' "$prompt" "$buffer"

  # Ghost suggestion (dim text after buffer)
  if [[ -n "$suggestion" && ${#buffer} -gt 0 ]]; then
    local ghost="${suggestion:${#buffer}}"
    printf '\033[2m%s\033[22m' "$ghost"
  fi

  # Move cursor back to correct position
  local chars_after=$(( ${#buffer} - cursor ))
  if [[ -n "$suggestion" && ${#buffer} -gt 0 ]]; then
    chars_after=$(( chars_after + ${#suggestion} - ${#buffer} ))
  fi
  if [[ $chars_after -gt 0 ]]; then
    printf '\033[%dD' "$chars_after"
  fi
}

readline_input() {
  local prompt="$1"
  local default="${2:-}"
  local use_history="${3:-true}"
  local use_completion="${4:-true}"

  local buffer=""
  local cursor=0
  local suggestion=""

  # Load history
  local -a hist_entries=()
  [[ "$use_history" == true ]] && _history_load hist_entries

  # Build display prompt with default hint
  local full_prompt
  if [[ -n "$default" ]]; then
    full_prompt="${prompt}[${default}]: "
  else
    full_prompt="${prompt}: "
  fi

  # Save terminal state
  local old_stty
  old_stty=$(stty -g)

  # Restore terminal on return (normal exit, error, or signal)
  trap 'stty "$old_stty" 2>/dev/null' RETURN

  # Raw-ish mode: no echo, no line buffering
  stty -echo -icanon min 1 time 0

  # Initial render
  _rl_render "$full_prompt" "$buffer" "$cursor" ""

  while true; do
    local char=""
    IFS= read -r -n1 char

    # Get ordinal (empty char = Enter in bash)
    local ord=0
    if [[ -n "$char" ]]; then
      ord=$(printf '%d' "'$char" 2>/dev/null) || ord=0
    fi

    # ── Enter ───────────────────────────────────────
    if [[ -z "$char" || "$ord" -eq 10 || "$ord" -eq 13 ]]; then
      break

    # ── Backspace ───────────────────────────────────
    elif [[ "$ord" -eq 127 || "$ord" -eq 8 ]]; then
      if [[ $cursor -gt 0 ]]; then
        buffer="${buffer:0:cursor-1}${buffer:cursor}"
        ((cursor--))
      fi

    # ── Ctrl+A  (beginning of line) ────────────────
    elif [[ "$ord" -eq 1 ]]; then
      cursor=0

    # ── Ctrl+E  (end of line / accept suggestion) ──
    elif [[ "$ord" -eq 5 ]]; then
      if [[ $cursor -eq ${#buffer} && -n "$suggestion" ]]; then
        buffer="$suggestion"
      fi
      cursor=${#buffer}

    # ── Ctrl+U  (clear entire line) ────────────────
    elif [[ "$ord" -eq 21 ]]; then
      buffer=""
      cursor=0

    # ── Ctrl+W  (delete word backward) ─────────────
    elif [[ "$ord" -eq 23 ]]; then
      if [[ $cursor -gt 0 ]]; then
        local before="${buffer:0:cursor}"
        local after="${buffer:cursor}"
        # Trim trailing spaces first
        while [[ ${#before} -gt 0 && "${before: -1}" == " " ]]; do
          before="${before:0:${#before}-1}"
        done
        # Then delete back to the previous separator (space or /)
        while [[ ${#before} -gt 0 && "${before: -1}" != " " && "${before: -1}" != "/" ]]; do
          before="${before:0:${#before}-1}"
        done
        buffer="${before}${after}"
        cursor=${#before}
      fi

    # ── Tab  (filesystem completion) ───────────────
    elif [[ "$ord" -eq 9 ]]; then
      if [[ "$use_completion" == true ]]; then
        local completed
        completed=$(_rl_tab_complete "$buffer")
        local tab_ret=$?
        if [[ $tab_ret -le 2 && -n "$completed" ]]; then
          buffer="$completed"
          cursor=${#buffer}
        fi
      fi

    # ── Escape sequences (arrows, home, end, del) ──
    elif [[ "$ord" -eq 27 ]]; then
      local seq1="" seq2="" seq3=""
      IFS= read -r -n1 -t 0.05 seq1 2>/dev/null || true
      if [[ "$seq1" == "[" ]]; then
        IFS= read -r -n1 -t 0.05 seq2 2>/dev/null || true
        case "$seq2" in
          C) # Right arrow (or accept suggestion at EOL)
            if [[ $cursor -lt ${#buffer} ]]; then
              ((cursor++))
            elif [[ -n "$suggestion" && $cursor -eq ${#buffer} ]]; then
              buffer="$suggestion"
              cursor=${#buffer}
            fi
            ;;
          D) # Left arrow
            [[ $cursor -gt 0 ]] && ((cursor--))
            ;;
          H) # Home
            cursor=0
            ;;
          F) # End (accept suggestion at EOL)
            if [[ $cursor -eq ${#buffer} && -n "$suggestion" ]]; then
              buffer="$suggestion"
            fi
            cursor=${#buffer}
            ;;
          3) # Delete  (ESC [ 3 ~)
            IFS= read -r -n1 -t 0.05 seq3 2>/dev/null || true
            if [[ "$seq3" == "~" && $cursor -lt ${#buffer} ]]; then
              buffer="${buffer:0:cursor}${buffer:cursor+1}"
            fi
            ;;
          1) # Home on some terminals (ESC [ 1 ~)
            IFS= read -r -n1 -t 0.05 seq3 2>/dev/null || true
            [[ "$seq3" == "~" ]] && cursor=0
            ;;
          4) # End on some terminals (ESC [ 4 ~)
            IFS= read -r -n1 -t 0.05 seq3 2>/dev/null || true
            if [[ "$seq3" == "~" ]]; then
              if [[ $cursor -eq ${#buffer} && -n "$suggestion" ]]; then
                buffer="$suggestion"
              fi
              cursor=${#buffer}
            fi
            ;;
        esac
      fi

    # ── Regular printable character ────────────────
    elif [[ "$ord" -ge 32 ]]; then
      buffer="${buffer:0:cursor}${char}${buffer:cursor}"
      ((cursor++))
    fi

    # Update ghost suggestion from history
    suggestion=""
    if [[ "$use_history" == true && -n "$buffer" ]]; then
      suggestion=$(_history_match "$buffer" hist_entries) || true
    fi

    _rl_render "$full_prompt" "$buffer" "$cursor" "$suggestion"
  done

  # Final clean line
  printf '\r\033[K%s%s\n' "$full_prompt" "$buffer"

  # Set return value
  if [[ -z "$buffer" ]]; then
    REPLY="$default"
  else
    REPLY="$buffer"
  fi

  # Persist to history
  if [[ "$use_history" == true && -n "$REPLY" ]]; then
    _history_save "$REPLY"
  fi
}

# ==================== SMART DETECTION ====================
detect_screen_resolution() {
  local detected=""

  # Try hyprctl first (Hyprland)
  if command -v hyprctl &>/dev/null; then
    detected=$(hyprctl monitors -j 2>/dev/null |
      grep -oP '"width":\s*\K\d+|"height":\s*\K\d+' |
      head -2 | tr '\n' 'x' | sed 's/x$//')
    if [[ -n "$detected" && "$detected" =~ ^[0-9]+x[0-9]+$ ]]; then
      echo "$detected"
      return 0
    fi
  fi

  # Try xrandr (X11/XWayland)
  if command -v xrandr &>/dev/null; then
    detected=$(xrandr 2>/dev/null | grep -oP '\d+x\d+' | head -1)
    if [[ -n "$detected" && "$detected" =~ ^[0-9]+x[0-9]+$ ]]; then
      echo "$detected"
      return 0
    fi
  fi

  # Try wlr-randr (wlroots compositors)
  if command -v wlr-randr &>/dev/null; then
    detected=$(wlr-randr 2>/dev/null | grep -oP '\d+x\d+' | head -1)
    if [[ -n "$detected" && "$detected" =~ ^[0-9]+x[0-9]+$ ]]; then
      echo "$detected"
      return 0
    fi
  fi

  # Fallback
  echo ""
  return 1
}

# ==================== QUALITY SETTINGS ====================
apply_quality_settings() {
  case "$VIDEO_QUALITY" in
  high)
    VIDEO_CRF=18
    WEBP_QUALITY=90
    ;;
  balanced)
    VIDEO_CRF=23
    WEBP_QUALITY=75
    ;;
  potato)
    VIDEO_CRF=28
    WEBP_QUALITY=50
    ;;
  *)
    VIDEO_CRF=23
    WEBP_QUALITY=75
    ;;
  esac
}

# ==================== OUTPUT CONFLICT HANDLING ====================
check_output_conflict() {
  if [[ "$PREVIEW_MODE" == true ]]; then
    return 0
  fi

  if [[ ! -d "$OUTPUT_DIR" ]]; then
    return 0
  fi

  local existing_count
  existing_count=$(find "$OUTPUT_DIR" -maxdepth 1 -type f -not -name '.*' 2>/dev/null | wc -l)

  if [[ $existing_count -eq 0 ]]; then
    return 0
  fi

  echo ""
  echo -e "${YELLOW}╭─────────────────────────────────────────────────────────╮${NC}"
  echo -e "${YELLOW}│${NC}   ${YELLOW}⚠️  Oops! Output folder has ${WHITE}${existing_count}${NC} file(s)... 🤔       ${YELLOW}│${NC}"
  echo -e "${YELLOW}╰─────────────────────────────────────────────────────────╯${NC}"
  echo ""
  echo -e "   ${WHITE}[M]${NC} ${GREEN}Merge${NC}  — Keep existing, overwrite on collision"
  echo -e "   ${WHITE}[W]${NC} ${RED}Wipe${NC}   — Delete everything first 🗑️"
  echo -e "   ${WHITE}[B]${NC} ${CYAN}Backup${NC} — Rename existing folder"
  echo ""

  local choice
  read -rp "   Choice [M]: " choice
  choice="${choice:-M}"

  case "${choice^^}" in
  M | MERGE)
    CONFLICT_MODE="merge"
    log_ok "Merge mode: keeping existing files 📁"
    ;;
  W | WIPE)
    CONFLICT_MODE="wipe"
    echo ""
    echo -e "   ${RED}${BOLD}⚠️  WARNING: This will DELETE all files!${NC}"
    read -rp "   Type 'yes' to confirm: " confirm
    if [[ "$confirm" == "yes" ]]; then
      find "$OUTPUT_DIR" -maxdepth 1 -type f -not -name '.*' -delete
      log_ok "Cleared! ✨"
    else
      CONFLICT_MODE="merge"
    fi
    ;;
  B | BACKUP)
    CONFLICT_MODE="backup"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="${OUTPUT_DIR}_backup_${timestamp}"
    if mv "$OUTPUT_DIR" "$backup_dir"; then
      mkdir -p "$OUTPUT_DIR"
      log_ok "Backup done! Fresh folder created ✨"
    else
      CONFLICT_MODE="merge"
    fi
    ;;
  *)
    CONFLICT_MODE="merge"
    ;;
  esac
  echo ""
  return 0
}

# ==================== RENAME FUNCTIONS ====================
prompt_rename_mode() {
  if [[ "$PREVIEW_MODE" == true ]]; then
    return 0
  fi

  echo ""
  echo -e "${CYAN}╭─────────────────────────────────────────────────────────╮${NC}"
  echo -e "${CYAN}│${NC}   ${CYAN}📝 How should I name the files? 🏷️${NC}                    ${CYAN}│${NC}"
  echo -e "${CYAN}╰─────────────────────────────────────────────────────────╯${NC}"
  echo ""
  echo -e "   ${WHITE}1)${NC} ${GREEN}Original${NC}   — Keep current names"
  echo -e "   ${WHITE}2)${NC} ${CYAN}Sequential${NC} — wall_001, wall_002..."
  echo -e "   ${WHITE}3)${NC} ${MAGENTA}Random${NC}     — bg_xxxx 🎲"
  echo ""

  local choice
  read -rp "   Choice [1]: " choice
  choice="${choice:-1}"

  case "$choice" in
  1) RENAME_MODE="original" ;;
  2) RENAME_MODE="sequential" ;;
  3) RENAME_MODE="random" ;;
  *) RENAME_MODE="original" ;;
  esac
}

apply_rename_mode() {
  local staging_dir="$1"

  if [[ "$RENAME_MODE" == "original" ]]; then
    return 0
  fi

  log_info "Applying $RENAME_MODE naming... 🏷️"

  mapfile -d '' files < <(find "$staging_dir" -maxdepth 1 -type f -not -name '.*' -print0 2>/dev/null | sort -z)

  if [[ ${#files[@]} -eq 0 ]]; then
    return 0
  fi

  local counter=1
  for file in "${files[@]}"; do
    [[ -z "$file" ]] && continue

    local ext="${file##*.}"
    local new_name=""

    case "$RENAME_MODE" in
    sequential)
      new_name=$(printf "wall_%03d.%s" "$counter" "$ext")
      ;;
    random)
      local rand_id=$(generate_random_id)
      new_name="bg_${rand_id}.${ext}"
      ;;
    esac

    if [[ -n "$new_name" && "$new_name" != "$(basename "$file")" ]]; then
      mv -- "$file" "$staging_dir/$new_name"
    fi

    ((counter++))
  done

  log_ok "Renamed ${#files[@]} files ✨"
}

# ==================== SCOPE MENU (v4.0) ====================
show_scope_menu() {
  echo ""
  echo -e "${MAGENTA}╭─────────────────────────────────────────────────────────╮${NC}"
  echo -e "${MAGENTA}│${NC}   ${CYAN}🥧 How many files? 📁${NC}                                 ${MAGENTA}│${NC}"
  echo -e "${MAGENTA}╰─────────────────────────────────────────────────────────╯${NC}"
  echo ""
  echo -e "   ${WHITE}1)${NC} ${GREEN}📄 Single File${NC}     ${DIM}(One image/video, quick bake)${NC}"
  echo -e "   ${WHITE}2)${NC} ${CYAN}📦 Bundle${NC}          ${DIM}(Bulk process a folder)${NC}"
  echo ""

  local choice
  read -rp "   Choice [1]: " choice
  choice="${choice:-1}"

  case "$choice" in
  1)
    SCOPE_MODE="single"
    log_ok "Single-file mode 📄"
    ;;
  2)
    SCOPE_MODE="bundle"
    log_ok "Bundle mode 📦"
    ;;
  *)
    log_warn "Invalid choice. Using Single mode."
    SCOPE_MODE="single"
    ;;
  esac
  echo ""
}

# ==================== SINGLE-FILE PROMPTS (v4.0) ====================
prompt_single_file() {
  echo ""
  echo -e "${BOLD}📄 SELECT FILE${NC}"
  echo -e "${DIM}   Path to the image or video${NC}"
  echo ""

  readline_input "   File" "" true true
  SINGLE_INPUT_FILE="${REPLY/#\~/$HOME}"

  # Validate it exists and is a file
  if [[ ! -f "$SINGLE_INPUT_FILE" ]]; then
    log_err "File does not exist: $SINGLE_INPUT_FILE"
    prompt_single_file
    return
  fi

  # Auto-detect whether it's an image or video
  local ext="${SINGLE_INPUT_FILE##*.}"
  ext="${ext,,}"
  case "$ext" in
    jpg|jpeg|png|webp|gif)
      BAKE_MODE="images"
      log_ok "Detected image: ${ext^^} 🖼️"
      ;;
    mp4|mkv|webm|avi|mov)
      BAKE_MODE="videos"
      log_ok "Detected video: ${ext^^} 🎬"
      ;;
    *)
      log_warn "Unknown extension '.${ext}' — treating as image"
      BAKE_MODE="images"
      ;;
  esac
}

prompt_save_mode() {
  echo ""
  echo -e "${CYAN}╭─────────────────────────────────────────────────────────╮${NC}"
  echo -e "${CYAN}│${NC}   ${CYAN}💾 What should I do with the result?${NC}                   ${CYAN}│${NC}"
  echo -e "${CYAN}╰─────────────────────────────────────────────────────────╯${NC}"
  echo ""
  echo -e "   ${WHITE}1)${NC} ${GREEN}💾 Save As${NC}      — New file alongside original"
  echo -e "   ${WHITE}2)${NC} ${MAGENTA}🔄 Replace${NC}     — Overwrite original"
  echo ""

  local choice
  read -rp "   Choice [1]: " choice
  choice="${choice:-1}"

  case "$choice" in
  1)
    SINGLE_SAVE_MODE="saveas"
    log_ok "Will save as new file 💾"
    ;;
  2)
    SINGLE_SAVE_MODE="replace"
    log_ok "Will replace original 🔄"
    ;;
  *)
    SINGLE_SAVE_MODE="saveas"
    ;;
  esac
}

# ==================== MAIN MENU ====================
show_main_menu() {
  echo ""
  echo -e "${MAGENTA}╭─────────────────────────────────────────────────────────╮${NC}"
  echo -e "${MAGENTA}│${NC}   ${CYAN}🥧 What are we baking today? 🍳${NC}                       ${MAGENTA}│${NC}"
  echo -e "${MAGENTA}╰─────────────────────────────────────────────────────────╯${NC}"
  echo ""
  echo -e "   ${WHITE}1)${NC} ${GREEN}🖼️  Still Images${NC}     ${DIM}(Resize, crop, optimize)${NC}"
  echo -e "   ${WHITE}2)${NC} ${MAGENTA}🎬 Live Wallpapers${NC}  ${DIM}(Convert videos → WebP/GIF)${NC}"
  echo ""

  local choice
  read -rp "   Choice [1]: " choice
  choice="${choice:-1}"

  case "$choice" in
  1)
    BAKE_MODE="images"
    log_ok "Image mode selected 🖼️"
    ;;
  2)
    BAKE_MODE="videos"
    log_ok "Video mode selected 🎬"
    ;;
  *)
    log_warn "Invalid choice. Using Image mode."
    BAKE_MODE="images"
    ;;
  esac
  echo ""
}

# ==================== VIDEO PROMPTS ====================
prompt_video_input_ext() {
  echo ""
  echo -e "${BOLD}🎥 INPUT VIDEO FORMAT${NC}"
  echo -e "${DIM}   What extension should I look for?${NC}"
  echo ""
  read -rp "   Extension [mp4]: " input_ext
  VIDEO_INPUT_EXT="${input_ext:-mp4}"
  VIDEO_INPUT_EXT="${VIDEO_INPUT_EXT#.}"
}

prompt_video_output_format() {
  echo ""
  echo -e "${BOLD}📦 OUTPUT FORMAT${NC}"
  echo -e "${DIM}   What should the videos become?${NC}"
  echo ""
  echo -e "   ${WHITE}1)${NC} ${GREEN}WebP${NC}  ${DIM}(Best for swww, smaller files)${NC} ⭐"
  echo -e "   ${WHITE}2)${NC} ${CYAN}GIF${NC}   ${DIM}(Classic, universal support)${NC}"
  echo -e "   ${WHITE}3)${NC} ${MAGENTA}MP4${NC}   ${DIM}(Just resize/optimize)${NC}"
  echo ""

  local choice
  read -rp "   Choice [1]: " choice
  choice="${choice:-1}"

  case "$choice" in
  1) VIDEO_OUTPUT_FORMAT="webp" ;;
  2) VIDEO_OUTPUT_FORMAT="gif" ;;
  3) VIDEO_OUTPUT_FORMAT="mp4" ;;
  *) VIDEO_OUTPUT_FORMAT="webp" ;;
  esac
}

prompt_video_duration() {
  echo ""
  echo -e "${BOLD}⏱️  VIDEO DURATION${NC}"
  echo -e "${DIM}   How much of each video to keep?${NC}"
  echo ""
  echo -e "   ${WHITE}1)${NC} ${YELLOW}Full Length${NC}    ${DIM}(⚠️  Warning: Large files!)${NC}"
  echo -e "   ${WHITE}2)${NC} ${GREEN}First 10 sec${NC}  ${DIM}(Best for loops)${NC} ⭐"
  echo -e "   ${WHITE}3)${NC} ${CYAN}First 30 sec${NC}  ${DIM}(Longer loops)${NC}"
  echo ""

  local choice
  read -rp "   Choice [2]: " choice
  choice="${choice:-2}"

  case "$choice" in
  1) VIDEO_DURATION="full" ;;
  2) VIDEO_DURATION="10" ;;
  3) VIDEO_DURATION="30" ;;
  *) VIDEO_DURATION="10" ;;
  esac
}

prompt_video_fps() {
  echo ""
  echo -e "${BOLD}🎞️  TARGET FPS${NC}"
  echo -e "${DIM}   What frame rate for the output?${NC}"
  echo ""
  echo -e "   ${WHITE}1)${NC} ${DIM}15 fps${NC}  ${DIM}— Low-Spec / Battery Saver${NC}"
  echo -e "   ${WHITE}2)${NC} ${YELLOW}24 fps${NC}  ${DIM}— Cinematic (Film-like)${NC}"
  echo -e "   ${WHITE}3)${NC} ${GREEN}30 fps${NC}  ${DIM}— Balanced (Recommended)${NC} ⭐"
  echo -e "   ${WHITE}4)${NC} ${CYAN}60 fps${NC}  ${DIM}— High-Performance${NC}"
  echo -e "   ${WHITE}5)${NC} ${MAGENTA}Custom${NC}  ${DIM}— Enter your own${NC}"
  echo ""

  local choice
  read -rp "   Choice [3]: " choice
  choice="${choice:-3}"

  case "$choice" in
  1) VIDEO_FPS=15 ;;
  2) VIDEO_FPS=24 ;;
  3) VIDEO_FPS=30 ;;
  4) VIDEO_FPS=60 ;;
  5)
    read -rp "   Enter custom FPS: " custom_fps
    if [[ "$custom_fps" =~ ^[0-9]+$ ]] && [[ "$custom_fps" -gt 0 ]] && [[ "$custom_fps" -le 120 ]]; then
      VIDEO_FPS=$custom_fps
    else
      log_warn "Invalid FPS. Using 30."
      VIDEO_FPS=30
    fi
    ;;
  *) VIDEO_FPS=30 ;;
  esac
}

prompt_video_quality() {
  echo ""
  echo -e "${BOLD}🎛️  QUALITY / COMPRESSION${NC}"
  echo -e "${DIM}   Balance between file size and quality${NC}"
  echo ""
  echo -e "   ${WHITE}1)${NC} ${GREEN}High${NC}      ${DIM}(CRF 18) — Big files, looks perfect${NC}"
  echo -e "   ${WHITE}2)${NC} ${CYAN}Balanced${NC}  ${DIM}(CRF 23) — Best for general use${NC} ⭐"
  echo -e "   ${WHITE}3)${NC} ${YELLOW}Potato${NC}    ${DIM}(CRF 28) — Tiny files, lowest CPU${NC}"
  echo ""

  local choice
  read -rp "   Choice [2]: " choice
  choice="${choice:-2}"

  case "$choice" in
  1) VIDEO_QUALITY="high" ;;
  2) VIDEO_QUALITY="balanced" ;;
  3) VIDEO_QUALITY="potato" ;;
  *) VIDEO_QUALITY="balanced" ;;
  esac

  apply_quality_settings
}

# ==================== INTERACTIVE PROMPTS ====================
prompt_source_dir() {
  local default_path="$PWD"

  # Check if PWD has files
  local file_count=$(find "$PWD" -maxdepth 1 -type f -not -name '.*' 2>/dev/null | wc -l)
  if [[ $file_count -eq 0 ]]; then
    echo ""
    echo -e "${YELLOW}⚠️  Current directory is empty!${NC}"
  fi

  echo ""
  echo -e "${BOLD}📁 SOURCE DIRECTORY${NC}"
  echo -e "${DIM}   Where are your files?${NC}"
  echo ""
  readline_input "   Path" "$default_path" true true
  SOURCE_DIR="${REPLY/#\~/$HOME}"

  if ! validate_directory "$SOURCE_DIR" "source"; then
    prompt_source_dir
  fi
}

prompt_output_dir() {
  local default_path="$SOURCE_DIR/baked"
  echo ""
  echo -e "${BOLD}💾 OUTPUT DIRECTORY${NC}"
  echo -e "${DIM}   Where should I put the results?${NC}"
  echo ""
  readline_input "   Path" "$default_path" true true
  OUTPUT_DIR="${REPLY/#\~/$HOME}"

  if ! validate_directory "$OUTPUT_DIR" "output"; then
    prompt_output_dir
  fi
}

prompt_resolution() {
  echo ""
  echo -e "${BOLD}📐 TARGET RESOLUTION${NC}"
  echo ""
  echo -e "   ${WHITE}0)${NC} ${MAGENTA}Auto-Detect${NC}  ${DIM}(Smart screen detection)${NC} 🤖"
  echo -e "   ${WHITE}1)${NC} 1920 x 1080  ${DIM}Full HD${NC}"
  echo -e "   ${WHITE}2)${NC} 2560 x 1440  ${DIM}2K${NC}"
  echo -e "   ${WHITE}3)${NC} 3840 x 2160  ${DIM}4K${NC}"
  echo -e "   ${WHITE}4)${NC} 1366 x 768   ${DIM}HD${NC}"
  echo -e "   ${WHITE}5)${NC} 1280 x 720   ${DIM}720p${NC}"
  echo -e "   ${WHITE}6)${NC} Custom..."
  echo ""
  read -rp "   Choice [1]: " choice
  choice="${choice:-1}"

  if [[ "$choice" == "0" ]]; then
    local detected=$(detect_screen_resolution)
    if [[ -n "$detected" ]]; then
      TARGET_RES="$detected"
      log_ok "Auto-detected: $TARGET_RES 🤖"
    else
      log_warn "Could not detect screen. Available tools: hyprctl, xrandr, wlr-randr"
      prompt_resolution
      return
    fi
  elif [[ -n "${PRESETS[$choice]:-}" ]]; then
    local preset="${PRESETS[$choice]}"
    local res="${preset%%|*}"

    if [[ "$res" == "custom" ]]; then
      read -rp "   Enter WIDTHxHEIGHT: " custom_res
      if validate_resolution "$custom_res"; then
        TARGET_RES="$custom_res"
      else
        prompt_resolution
        return
      fi
    elif [[ "$res" == "auto" ]]; then
      local detected=$(detect_screen_resolution)
      if [[ -n "$detected" ]]; then
        TARGET_RES="$detected"
        log_ok "Auto-detected: $TARGET_RES 🤖"
      else
        log_warn "Could not detect screen."
        prompt_resolution
        return
      fi
    else
      TARGET_RES="$res"
    fi
  else
    prompt_resolution
    return
  fi

  WIDTH="${TARGET_RES%x*}"
  HEIGHT="${TARGET_RES#*x}"
}

prompt_preview() {
  echo ""
  echo -e "${BOLD}👁️  PREVIEW MODE${NC}"
  read -rp "   Preview only? (dry run) [y/N]: " preview_choice
  if [[ "${preview_choice,,}" == "y" ]]; then
    PREVIEW_MODE=true
  fi
}

prompt_confirm() {
  local mode_text
  if [[ "$PREVIEW_MODE" == true ]]; then
    mode_text="🔍 Preview"
  else
    mode_text="🚀 Processing"
  fi

  local bake_text
  if [[ "$BAKE_MODE" == "videos" ]]; then
    bake_text="🎬 Videos → ${VIDEO_OUTPUT_FORMAT^^}"
  else
    bake_text="🖼️  Images"
  fi

  local quality_text="${VIDEO_QUALITY^} (CRF ${VIDEO_CRF})"

  echo ""
  echo -e "${MAGENTA}╭─────────────────────────────────────────────────────────╮${NC}"
  echo -e "${MAGENTA}│${NC}        ${CYAN}✨ Ready to bake? Here's the recipe! ✨${NC}         ${MAGENTA}│${NC}"
  echo -e "${MAGENTA}├─────────────────────────────────────────────────────────┤${NC}"
  printf "${MAGENTA}│${NC}  ${DIM}Type:${NC}       %-38s  ${MAGENTA}│${NC}\n" "$bake_text"

  if [[ "$SCOPE_MODE" == "single" ]]; then
    # Single-file specific info
    local file_display
    file_display=$(basename "$SINGLE_INPUT_FILE")
    local save_display
    if [[ "$SINGLE_SAVE_MODE" == "replace" ]]; then
      save_display="🔄 Replace original"
    else
      save_display="💾 Save as new file"
    fi
    printf "${MAGENTA}│${NC}  ${DIM}File:${NC}       %-38s  ${MAGENTA}│${NC}\n" "$file_display"
    printf "${MAGENTA}│${NC}  ${DIM}Resolution:${NC} %-38s  ${MAGENTA}│${NC}\n" "${WIDTH}x${HEIGHT}"
    if [[ "$BAKE_MODE" == "videos" ]]; then
      printf "${MAGENTA}│${NC}  ${DIM}Duration:${NC}   %-38s  ${MAGENTA}│${NC}\n" "${VIDEO_DURATION}s"
      printf "${MAGENTA}│${NC}  ${DIM}FPS:${NC}        %-38s  ${MAGENTA}│${NC}\n" "$VIDEO_FPS"
      printf "${MAGENTA}│${NC}  ${DIM}Quality:${NC}    %-38s  ${MAGENTA}│${NC}\n" "$quality_text"
    fi
    printf "${MAGENTA}│${NC}  ${DIM}Save:${NC}       %-38s  ${MAGENTA}│${NC}\n" "$save_display"
  else
    # Bundle mode info
    printf "${MAGENTA}│${NC}  ${DIM}Source:${NC}     %-38s  ${MAGENTA}│${NC}\n" "$SOURCE_DIR"
    printf "${MAGENTA}│${NC}  ${DIM}Output:${NC}     %-38s  ${MAGENTA}│${NC}\n" "$OUTPUT_DIR"
    printf "${MAGENTA}│${NC}  ${DIM}Resolution:${NC} %-38s  ${MAGENTA}│${NC}\n" "${WIDTH}x${HEIGHT}"
    if [[ "$BAKE_MODE" == "videos" ]]; then
      printf "${MAGENTA}│${NC}  ${DIM}Duration:${NC}   %-38s  ${MAGENTA}│${NC}\n" "${VIDEO_DURATION}s"
      printf "${MAGENTA}│${NC}  ${DIM}FPS:${NC}        %-38s  ${MAGENTA}│${NC}\n" "$VIDEO_FPS"
      printf "${MAGENTA}│${NC}  ${DIM}Quality:${NC}    %-38s  ${MAGENTA}│${NC}\n" "$quality_text"
    fi
  fi

  printf "${MAGENTA}│${NC}  ${DIM}Threads:${NC}    %-38s  ${MAGENTA}│${NC}\n" "$CPU_THREADS"
  printf "${MAGENTA}│${NC}  ${DIM}Mode:${NC}       %-38s  ${MAGENTA}│${NC}\n" "$mode_text"
  echo -e "${MAGENTA}╰─────────────────────────────────────────────────────────╯${NC}"
  echo ""
  read -rp "   Proceed? [Y/n]: " confirm
  if [[ "${confirm,,}" == "n" ]]; then
    log_warn "Aborted! See you next time! 👋"
    exit 0
  fi
}

run_interactive_mode() {
  show_banner
  show_scope_menu

  if [[ "$SCOPE_MODE" == "single" ]]; then
    # ── Single-file flow ──
    prompt_single_file
    prompt_resolution

    if [[ "$BAKE_MODE" == "videos" ]]; then
      prompt_video_output_format
      prompt_video_duration
      prompt_video_fps
      prompt_video_quality
    fi

    prompt_save_mode
    prompt_preview
    prompt_confirm
  else
    # ── Bundle flow (original) ──
    show_main_menu
    prompt_source_dir
    prompt_output_dir
    prompt_resolution

    if [[ "$BAKE_MODE" == "videos" ]]; then
      prompt_video_input_ext
      prompt_video_output_format
      prompt_video_duration
      prompt_video_fps
      prompt_video_quality
    fi

    prompt_preview
    prompt_confirm
    check_output_conflict
  fi
}

# ==================== ARGUMENT PARSING ====================
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -s | --source)
      SOURCE_DIR="${2:-}"
      SOURCE_DIR="${SOURCE_DIR/#\~/$HOME}"
      shift 2
      ;;
    -o | --output)
      OUTPUT_DIR="${2:-}"
      OUTPUT_DIR="${OUTPUT_DIR/#\~/$HOME}"
      shift 2
      ;;
    -r | --res)
      TARGET_RES="${2:-}"
      shift 2
      ;;
    -m | --mode)
      case "${2,,}" in
      images | image) BAKE_MODE="images" ;;
      videos | video) BAKE_MODE="videos" ;;
      *)
        log_err "Invalid mode: $2"
        exit 1
        ;;
      esac
      shift 2
      ;;
    -p | --preview)
      PREVIEW_MODE=true
      shift
      ;;
    --single)
      SCOPE_MODE="single"
      SINGLE_INPUT_FILE="${2:-}"
      SINGLE_INPUT_FILE="${SINGLE_INPUT_FILE/#\~/$HOME}"
      shift 2
      ;;
    --save-mode)
      case "${2,,}" in
      saveas | replace) SINGLE_SAVE_MODE="${2,,}" ;;
      *)
        log_err "Invalid save mode: $2 (use: saveas|replace)"
        exit 1
        ;;
      esac
      shift 2
      ;;
    --conflict)
      CONFLICT_MODE="${2,,}"
      shift 2
      ;;
    --rename)
      RENAME_MODE="${2,,}"
      shift 2
      ;;
    --input-ext)
      VIDEO_INPUT_EXT="${2#.}"
      shift 2
      ;;
    --format)
      case "${2,,}" in
      webp | gif | mp4) VIDEO_OUTPUT_FORMAT="${2,,}" ;;
      *)
        log_err "Invalid format: $2"
        exit 1
        ;;
      esac
      shift 2
      ;;
    --duration)
      VIDEO_DURATION="${2:-10}"
      shift 2
      ;;
    --fps)
      if [[ "${2:-30}" =~ ^[0-9]+$ ]]; then
        VIDEO_FPS="${2:-30}"
      else
        log_err "Invalid FPS: $2"
        exit 1
      fi
      shift 2
      ;;
    --quality)
      case "${2,,}" in
      high | balanced | potato) VIDEO_QUALITY="${2,,}" ;;
      *)
        log_err "Invalid quality: $2"
        exit 1
        ;;
      esac
      apply_quality_settings
      shift 2
      ;;
    -h | --help)
      show_help
      exit 0
      ;;
    -v | --version)
      show_version
      exit 0
      ;;
    *)
      log_err "Unknown option: $1"
      exit 1
      ;;
    esac
  done

  if [[ -n "$SINGLE_INPUT_FILE" || -n "$SOURCE_DIR" || -n "$OUTPUT_DIR" || -n "$TARGET_RES" ]]; then
    INTERACTIVE_MODE=false
  fi
}

validate_cli_args() {
  local has_error=false

  # Single-file mode validation
  if [[ "$SCOPE_MODE" == "single" ]]; then
    if [[ ! -f "$SINGLE_INPUT_FILE" ]]; then
      log_err "File not found: $SINGLE_INPUT_FILE"
      has_error=true
    fi

    if [[ -z "$TARGET_RES" ]]; then
      log_err "Resolution required (--res)"
      has_error=true
    elif ! validate_resolution "$TARGET_RES"; then
      has_error=true
    fi

    # Auto-detect bake mode from extension
    if [[ -z "$BAKE_MODE" && -f "$SINGLE_INPUT_FILE" ]]; then
      local ext="${SINGLE_INPUT_FILE##*.}"
      ext="${ext,,}"
      case "$ext" in
        jpg|jpeg|png|webp|gif) BAKE_MODE="images" ;;
        mp4|mkv|webm|avi|mov) BAKE_MODE="videos" ;;
        *) BAKE_MODE="images" ;;
      esac
    fi

    [[ -z "$SINGLE_SAVE_MODE" ]] && SINGLE_SAVE_MODE="saveas"

    if [[ "$has_error" == true ]]; then
      exit 1
    fi

    WIDTH="${TARGET_RES%x*}"
    HEIGHT="${TARGET_RES#*x}"
    apply_quality_settings
    return
  fi

  # Bundle mode validation (original)
  if [[ -z "$SOURCE_DIR" ]]; then
    SOURCE_DIR="$PWD"
    log_info "Using current directory as source: $SOURCE_DIR"
  fi

  if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="$SOURCE_DIR/baked"
    log_info "Using default output: $OUTPUT_DIR"
  fi

  if [[ -z "$TARGET_RES" ]]; then
    log_err "Resolution required (--res)"
    has_error=true
  elif ! validate_resolution "$TARGET_RES"; then
    has_error=true
  fi

  if [[ -z "$BAKE_MODE" ]]; then
    BAKE_MODE="images"
  fi

  if [[ "$has_error" == true ]]; then
    exit 1
  fi

  mkdir -p "$OUTPUT_DIR"

  WIDTH="${TARGET_RES%x*}"
  HEIGHT="${TARGET_RES#*x}"

  apply_quality_settings
}

# ==================== SINGLE-FILE PROCESSING (v4.0) ====================
readonly BAKERY_TRASH_DIR="/tmp/hyprbakery_trash"

process_single_image() {
  local file="$SINGLE_INPUT_FILE"
  local base_name ext_lower name_noext dir_path
  base_name=$(basename "$file")
  dir_path=$(dirname "$file")
  ext_lower="${base_name##*.}"
  ext_lower="${ext_lower,,}"
  name_noext="${base_name%.*}"

  echo ""
  echo -e "${MAGENTA}╭─────────────────────────────────────────────────────────╮${NC}"
  echo -e "${MAGENTA}│${NC}   ${GREEN}🖼️  ${PREVIEW_MODE:+Preview: }Baking single image... (~˘▾˘)~${NC}          ${MAGENTA}│${NC}"
  echo -e "${MAGENTA}╰─────────────────────────────────────────────────────────╯${NC}"
  echo ""

  # Handle GIFs
  if [[ "$ext_lower" == "gif" ]]; then
    if [[ "$PREVIEW_MODE" == true ]]; then
      log_gif "Would copy GIF as-is: $base_name"
    else
      log_gif "GIF — nothing to resize, already perfect ✨"
    fi
    return
  fi

  # Skip unsupported
  if [[ ! "$ext_lower" =~ ^(jpg|jpeg|png|webp)$ ]]; then
    log_err "Unsupported format: .$ext_lower"
    return
  fi

  # Get current dimensions
  local dimensions
  dimensions=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=width,height -of csv=s=x:p=0 -- "$file" 2>/dev/null) || true

  if [[ -z "$dimensions" ]]; then
    log_err "Could not read image: $base_name"
    return
  fi

  if [[ "$dimensions" == "$TARGET_RES" ]]; then
    log_skip "Already ${TARGET_RES} — nothing to do ✨"
    return
  fi

  # Output extension
  local output_ext
  case "$ext_lower" in
    jpg|jpeg) output_ext="jpg" ;;
    png) output_ext="png" ;;
    webp) output_ext="png" ;;
  esac

  if [[ "$PREVIEW_MODE" == true ]]; then
    log_fix "Would resize: $base_name ($dimensions → ${TARGET_RES})"
    return
  fi

  log_fix "Resizing: $base_name ($dimensions → ${TARGET_RES})"

  # Build output path based on save mode
  local output_path
  if [[ "$SINGLE_SAVE_MODE" == "replace" ]]; then
    output_path="${dir_path}/.bakery_tmp_${base_name}"
  else
    output_path="${dir_path}/${name_noext}_baked.${output_ext}"
  fi

  local ffmpeg_opts=(-hide_banner -loglevel error -y -threads "$CPU_THREADS" -i "$file")
  ffmpeg_opts+=(-vf "scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT}")
  ffmpeg_opts+=(-sws_flags lanczos)
  [[ "$output_ext" == "jpg" ]] && ffmpeg_opts+=(-q:v 2)

  if ffmpeg "${ffmpeg_opts[@]}" "$output_path" 2>/dev/null; then
    if [[ "$SINGLE_SAVE_MODE" == "replace" ]]; then
      # Move original to trash, then put result in its place
      mkdir -p "$BAKERY_TRASH_DIR"
      mv -- "$file" "$BAKERY_TRASH_DIR/$base_name"
      mv -- "$output_path" "$file"
      log_ok "Replaced! Original saved to $BAKERY_TRASH_DIR/ 🗑️"
    else
      log_ok "Saved: $(basename "$output_path") ✨"
    fi
  else
    log_err "FFMPEG failed: $base_name"
    rm -f "$output_path"
  fi
}

process_single_video() {
  local file="$SINGLE_INPUT_FILE"
  local base_name ext_lower name_noext dir_path
  base_name=$(basename "$file")
  dir_path=$(dirname "$file")
  ext_lower="${base_name##*.}"
  ext_lower="${ext_lower,,}"
  name_noext="${base_name%.*}"

  echo ""
  echo -e "${MAGENTA}╭─────────────────────────────────────────────────────────╮${NC}"
  echo -e "${MAGENTA}│${NC}   ${MAGENTA}🎬 ${PREVIEW_MODE:+Preview: }Baking single video... ~(˘▾˘)~${NC}          ${MAGENTA}│${NC}"
  echo -e "${MAGENTA}╰─────────────────────────────────────────────────────────╯${NC}"
  echo ""

  if [[ "$PREVIEW_MODE" == true ]]; then
    log_vid "Would convert: $base_name → ${VIDEO_OUTPUT_FORMAT^^}"
    return
  fi

  log_vid "Converting: $base_name → ${VIDEO_OUTPUT_FORMAT^^}"

  # Build output path based on save mode
  local output_path
  if [[ "$SINGLE_SAVE_MODE" == "replace" ]]; then
    output_path="${dir_path}/.bakery_tmp_${name_noext}.${VIDEO_OUTPUT_FORMAT}"
  else
    output_path="${dir_path}/${name_noext}_baked.${VIDEO_OUTPUT_FORMAT}"
  fi

  local scale_filter="scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT}"
  local ffmpeg_cmd=(ffmpeg -hide_banner -loglevel error -y -threads "$CPU_THREADS")

  if [[ "$VIDEO_DURATION" != "full" ]]; then
    ffmpeg_cmd+=(-t "$VIDEO_DURATION")
  fi
  ffmpeg_cmd+=(-i "$file")

  local success=false

  case "$VIDEO_OUTPUT_FORMAT" in
  webp)
    ffmpeg_cmd+=(-vf "${scale_filter},fps=${VIDEO_FPS}")
    ffmpeg_cmd+=(-vcodec libwebp)
    ffmpeg_cmd+=(-lossless 0 -q:v "$WEBP_QUALITY" -loop 0 -preset default)
    ffmpeg_cmd+=(-an)
    "${ffmpeg_cmd[@]}" "$output_path" 2>/dev/null && success=true
    ;;
  gif)
    local palette_file="${dir_path}/.bakery_palette_$$.png"
    ffmpeg -hide_banner -loglevel error -y -threads "$CPU_THREADS" \
      ${VIDEO_DURATION:+-t "$VIDEO_DURATION"} \
      -i "$file" \
      -vf "${scale_filter},fps=${VIDEO_FPS},palettegen=stats_mode=diff" \
      "$palette_file" 2>/dev/null

    if [[ -f "$palette_file" ]]; then
      ffmpeg -hide_banner -loglevel error -y -threads "$CPU_THREADS" \
        ${VIDEO_DURATION:+-t "$VIDEO_DURATION"} \
        -i "$file" -i "$palette_file" \
        -lavfi "${scale_filter},fps=${VIDEO_FPS} [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=5" \
        "$output_path" 2>/dev/null && success=true
      rm -f "$palette_file"
    else
      ffmpeg_cmd+=(-vf "${scale_filter},fps=${VIDEO_FPS}")
      "${ffmpeg_cmd[@]}" "$output_path" 2>/dev/null && success=true
    fi
    ;;
  mp4)
    ffmpeg_cmd+=(-vf "$scale_filter")
    ffmpeg_cmd+=(-c:v libx264 -preset fast -crf "$VIDEO_CRF")
    ffmpeg_cmd+=(-an)
    "${ffmpeg_cmd[@]}" "$output_path" 2>/dev/null && success=true
    ;;
  esac

  if [[ "$success" == true && -f "$output_path" ]]; then
    if [[ "$SINGLE_SAVE_MODE" == "replace" ]]; then
      mkdir -p "$BAKERY_TRASH_DIR"
      mv -- "$file" "$BAKERY_TRASH_DIR/$base_name"
      mv -- "$output_path" "${dir_path}/${name_noext}.${VIDEO_OUTPUT_FORMAT}"
      log_ok "Replaced! Original saved to $BAKERY_TRASH_DIR/ 🗑️"
    else
      log_ok "Saved: $(basename "$output_path") ✨"
    fi
  else
    log_err "FFMPEG failed: $base_name"
    rm -f "$output_path"
  fi
}

# ==================== IMAGE PROCESSING ====================
process_images() {
  local staging_dir="$OUTPUT_DIR/.bakery_staging"

  trap cleanup EXIT

  if [[ -d "$staging_dir" ]]; then
    rm -rf "$staging_dir"
  fi
  mkdir -p "$staging_dir"

  echo ""
  echo -e "${MAGENTA}╭─────────────────────────────────────────────────────────╮${NC}"
  echo -e "${MAGENTA}│${NC}   ${GREEN}🖼️  ${PREVIEW_MODE:+Preview: }Baking images... (~˘▾˘)~${NC}                ${MAGENTA}│${NC}"
  echo -e "${MAGENTA}╰─────────────────────────────────────────────────────────╯${NC}"
  echo ""

  mapfile -d '' files < <(find "$SOURCE_DIR" -maxdepth 1 -type f -not -name '.*' -print0 2>/dev/null)
  count_total=${#files[@]}

  if [[ $count_total -eq 0 ]]; then
    log_warn "No files found!"
    return
  fi

  log_info "Found $count_total file(s)... Let's bake! 🥧"
  log_info "Using $CPU_THREADS CPU threads"
  echo ""

  local current=0
  for file in "${files[@]}"; do
    [[ -z "$file" ]] && continue
    ((current++))

    local base_name ext_lower name_noext
    base_name=$(basename "$file")
    ext_lower="${base_name##*.}"
    ext_lower="${ext_lower,,}"
    name_noext="${base_name%.*}"

    local cleaned_name=$(clean_filename "$name_noext")
    local display_name=$(get_display_name "$cleaned_name")
    local progress="[$current/$count_total]"

    # Handle GIFs
    if [[ "$ext_lower" == "gif" ]]; then
      local gif_output="${cleaned_name}.gif"
      if [[ "$PREVIEW_MODE" == true ]]; then
        log_gif "$progress Would copy: $display_name"
      else
        log_gif "$progress Copying: $display_name"
        cp -- "$file" "$staging_dir/$gif_output" && ((count_gifs++)) || ((count_errors++))
      fi
      continue
    fi

    # Skip non-images
    if [[ ! "$ext_lower" =~ ^(jpg|jpeg|png|webp)$ ]]; then
      continue
    fi

    # Output extension
    local output_ext
    case "$ext_lower" in
    jpg | jpeg) output_ext="jpg" ;;
    png) output_ext="png" ;;
    webp) output_ext="png" ;;
    esac

    local output_name="${cleaned_name}_${TARGET_RES}.${output_ext}"

    # Get dimensions
    local dimensions
    dimensions=$(ffprobe -v error -select_streams v:0 \
      -show_entries stream=width,height -of csv=s=x:p=0 -- "$file" 2>/dev/null) || true

    if [[ -z "$dimensions" ]]; then
      log_err "$progress Corrupted: $display_name"
      ((count_errors++))
      continue
    fi

    if [[ "$dimensions" == "$TARGET_RES" ]]; then
      log_skip "$progress Already ${TARGET_RES}: $display_name"
      [[ "$PREVIEW_MODE" != true ]] && cp -- "$file" "$staging_dir/$output_name"
      ((count_skipped++))
    else
      if [[ "$PREVIEW_MODE" == true ]]; then
        log_fix "$progress Would resize: $display_name"
      else
        log_fix "$progress Resizing: $display_name"

        local ffmpeg_opts=(-hide_banner -loglevel error -y -threads "$CPU_THREADS" -i "$file")
        ffmpeg_opts+=(-vf "scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT}")
        ffmpeg_opts+=(-sws_flags lanczos)
        [[ "$output_ext" == "jpg" ]] && ffmpeg_opts+=(-q:v 2)

        if ffmpeg "${ffmpeg_opts[@]}" "$staging_dir/$output_name" 2>/dev/null; then
          ((count_processed++))
        else
          log_err "FFMPEG failed: $display_name"
          ((count_errors++))
        fi
      fi
      [[ "$PREVIEW_MODE" == true ]] && ((count_processed++))
    fi
  done

  if [[ "$PREVIEW_MODE" == true ]]; then
    show_summary
    return
  fi

  [[ "$INTERACTIVE_MODE" == true ]] && prompt_rename_mode
  apply_rename_mode "$staging_dir"
  finalize_output "$staging_dir"
}

# ==================== VIDEO PROCESSING ====================
process_videos() {
  local staging_dir="$OUTPUT_DIR/.bakery_staging"

  trap cleanup EXIT

  if [[ -d "$staging_dir" ]]; then
    rm -rf "$staging_dir"
  fi
  mkdir -p "$staging_dir"

  echo ""
  echo -e "${MAGENTA}╭─────────────────────────────────────────────────────────╮${NC}"
  echo -e "${MAGENTA}│${NC}   ${MAGENTA}🎬 ${PREVIEW_MODE:+Preview: }Baking videos... ~(˘▾˘)~${NC}                 ${MAGENTA}│${NC}"
  echo -e "${MAGENTA}╰─────────────────────────────────────────────────────────╯${NC}"
  echo ""

  # Find videos with the specified extension
  mapfile -d '' files < <(find "$SOURCE_DIR" -maxdepth 1 -type f -iname "*.${VIDEO_INPUT_EXT}" -print0 2>/dev/null)
  count_total=${#files[@]}

  if [[ $count_total -eq 0 ]]; then
    log_warn "No *.${VIDEO_INPUT_EXT} files found!"
    return
  fi

  log_info "Found $count_total video(s)... Let's bake! 🥧"
  log_info "Output: ${VIDEO_OUTPUT_FORMAT^^} @ ${WIDTH}x${HEIGHT} @ ${VIDEO_FPS}fps"
  log_info "Quality: ${VIDEO_QUALITY^} (CRF ${VIDEO_CRF}) • Threads: $CPU_THREADS"
  echo ""

  local current=0
  for file in "${files[@]}"; do
    [[ -z "$file" ]] && continue
    ((current++))

    local base_name name_noext
    base_name=$(basename "$file")
    name_noext="${base_name%.*}"

    local cleaned_name=$(clean_filename "$name_noext")
    local display_name=$(get_display_name "$cleaned_name")
    local progress="[$current/$count_total]"

    local output_name="${cleaned_name}_${TARGET_RES}.${VIDEO_OUTPUT_FORMAT}"

    if [[ "$PREVIEW_MODE" == true ]]; then
      log_vid "$progress Would convert: $display_name → ${VIDEO_OUTPUT_FORMAT^^}"
      ((count_processed++))
      continue
    fi

    log_vid "$progress Converting: $display_name"

    # Build ffmpeg command based on output format
    local ffmpeg_cmd=(ffmpeg -hide_banner -loglevel error -y -threads "$CPU_THREADS")

    # Duration trimming
    if [[ "$VIDEO_DURATION" != "full" ]]; then
      ffmpeg_cmd+=(-t "$VIDEO_DURATION")
    fi

    ffmpeg_cmd+=(-i "$file")

    # Scale filter
    local scale_filter="scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=increase,crop=${WIDTH}:${HEIGHT}"

    case "$VIDEO_OUTPUT_FORMAT" in
    webp)
      # WebP (The swww Special)
      ffmpeg_cmd+=(-vf "${scale_filter},fps=${VIDEO_FPS}")
      ffmpeg_cmd+=(-vcodec libwebp)
      ffmpeg_cmd+=(-lossless 0 -q:v "$WEBP_QUALITY" -loop 0 -preset default)
      ffmpeg_cmd+=(-an) # Remove audio
      ;;
    gif)
      # High-quality GIF with palette
      local palette_file="${staging_dir}/palette_$$.png"

      # Generate palette
      ffmpeg -hide_banner -loglevel error -y -threads "$CPU_THREADS" \
        ${VIDEO_DURATION:+-t "$VIDEO_DURATION"} \
        -i "$file" \
        -vf "${scale_filter},fps=${VIDEO_FPS},palettegen=stats_mode=diff" \
        "$palette_file" 2>/dev/null

      if [[ -f "$palette_file" ]]; then
        # Use palette for high-quality GIF
        ffmpeg -hide_banner -loglevel error -y -threads "$CPU_THREADS" \
          ${VIDEO_DURATION:+-t "$VIDEO_DURATION"} \
          -i "$file" -i "$palette_file" \
          -lavfi "${scale_filter},fps=${VIDEO_FPS} [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=5" \
          "$staging_dir/$output_name" 2>/dev/null
        rm -f "$palette_file"

        if [[ -f "$staging_dir/$output_name" ]]; then
          ((count_processed++))
        else
          ((count_errors++))
        fi
        continue
      else
        # Fallback to basic scaling
        ffmpeg_cmd+=(-vf "${scale_filter},fps=${VIDEO_FPS}")
      fi
      ;;
    mp4)
      # Optimized MP4
      ffmpeg_cmd+=(-vf "$scale_filter")
      ffmpeg_cmd+=(-c:v libx264 -preset fast -crf "$VIDEO_CRF")
      ffmpeg_cmd+=(-an) # Remove audio
      ;;
    esac

    if "${ffmpeg_cmd[@]}" "$staging_dir/$output_name" 2>/dev/null; then
      ((count_processed++))
    else
      log_err "FFMPEG failed: $display_name"
      ((count_errors++))
    fi
  done

  if [[ "$PREVIEW_MODE" == true ]]; then
    show_summary
    return
  fi

  [[ "$INTERACTIVE_MODE" == true ]] && prompt_rename_mode
  apply_rename_mode "$staging_dir"
  finalize_output "$staging_dir"
}

# ==================== FINALIZE OUTPUT ====================
finalize_output() {
  local staging_dir="$1"

  echo ""
  log_info "Moving files to output... 📦"

  local final_count=0
  while IFS= read -r -d '' staging_file; do
    local out_name=$(basename "$staging_file")

    if [[ "$CONFLICT_MODE" == "merge" && -f "$OUTPUT_DIR/$out_name" ]]; then
      local ts=$(date +%s)
      local name_part="${out_name%.*}"
      local ext_part="${out_name##*.}"
      out_name="${name_part}_${ts}.${ext_part}"
    fi

    mv -- "$staging_file" "$OUTPUT_DIR/$out_name"
    ((final_count++))
  done < <(find "$staging_dir" -maxdepth 1 -type f -print0 2>/dev/null)

  cleanup
  show_summary "$final_count"
}

# ==================== SUMMARY ====================
show_summary() {
  local final_count="${1:-$count_processed}"

  local output_display="$OUTPUT_DIR"
  if [[ ${#output_display} -gt 35 ]]; then
    output_display="...${output_display: -32}"
  fi

  echo ""
  echo -e "${MAGENTA}╭─────────────────────────────────────────────────────────╮${NC}"
  echo -e "${MAGENTA}│${NC}                                                         ${MAGENTA}│${NC}"
  echo -e "${MAGENTA}│${NC}   ${GREEN}🥧✨ ~(˘▾˘~)${NC} ${PREVIEW_MODE:+PREVIEW }ALL BAKED! ${GREEN}(~˘▾˘)~ ✨🥧${NC}       ${MAGENTA}│${NC}"
  echo -e "${MAGENTA}│${NC}                                                         ${MAGENTA}│${NC}"
  echo -e "${MAGENTA}├─────────────────────────────────────────────────────────┤${NC}"

  if [[ "$BAKE_MODE" == "videos" ]]; then
    printf "${MAGENTA}│${NC}   ${GREEN}🎬 Converted:${NC}  %-5s videos                       ${MAGENTA}│${NC}\n" "$count_processed"
    printf "${MAGENTA}│${NC}   ${RED}💥 Errors:${NC}     %-5s                              ${MAGENTA}│${NC}\n" "$count_errors"
  else
    printf "${MAGENTA}│${NC}   ${GREEN}🔧 Resized:${NC}    %-5s images                       ${MAGENTA}│${NC}\n" "$count_processed"
    printf "${MAGENTA}│${NC}   ${CYAN}⏭️  Perfect:${NC}    %-5s already correct              ${MAGENTA}│${NC}\n" "$count_skipped"
    printf "${MAGENTA}│${NC}   ${BLUE}👾 GIFs:${NC}       %-5s copied                        ${MAGENTA}│${NC}\n" "$count_gifs"
    printf "${MAGENTA}│${NC}   ${RED}💥 Errors:${NC}     %-5s                              ${MAGENTA}│${NC}\n" "$count_errors"
  fi

  if [[ "$PREVIEW_MODE" != true ]]; then
    echo -e "${MAGENTA}├─────────────────────────────────────────────────────────┤${NC}"
    echo -e "${MAGENTA}│${NC}   ${DIM}📁 Output: ${output_display}${NC}"
  fi

  echo -e "${MAGENTA}├─────────────────────────────────────────────────────────┤${NC}"
  echo -e "${MAGENTA}│${NC}   ${DIM}Your wallpapers are looking delicious! 💖${NC}            ${MAGENTA}│${NC}"
  echo -e "${MAGENTA}╰─────────────────────────────────────────────────────────╯${NC}"
  echo ""
}

# ==================== MAIN ====================
main() {
  check_dependencies

  parse_args "$@"

  if [[ "$INTERACTIVE_MODE" == true ]]; then
    run_interactive_mode
  else
    show_banner
    validate_cli_args
  fi

  # Dispatch: single-file vs bundle
  if [[ "$SCOPE_MODE" == "single" ]]; then
    if [[ "$BAKE_MODE" == "videos" ]]; then
      process_single_video
    else
      process_single_image
    fi
  else
    if [[ "$BAKE_MODE" == "videos" ]]; then
      process_videos
    else
      process_images
    fi
  fi
}

main "$@"
