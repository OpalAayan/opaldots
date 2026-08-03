#!/bin/bash
#
# ╭─────────────────────────────────────────────────────────╮
# │      🥧✨ ~(˘▾˘~) HYPR-BAKERY v3.5 (~˘▾˘)~ ✨🥧         │
# │                  ~ Universal Edition ~                  │
# │                                                         │
# │  The Swiss Army Knife for Wallpapers! Made with 💖      │
# │  • Still Images (Resize, crop, optimize)                │
# │  • Live Wallpapers (Video → WebP/GIF/MP4)               │
# ╰─────────────────────────────────────────────────────────╯
#

set -uo pipefail

# ==================== CONSTANTS ====================
readonly VERSION="3.5"
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
  for cmd in ffmpeg ffprobe bc; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_err "Missing required tools: ${missing[*]}"
    echo ""
    echo -e "    ${DIM}Install with:${NC}"
    echo -e "    ${CYAN}sudo pacman -S ffmpeg bc${NC}    ${DIM}(Arch)${NC}"
    echo -e "    ${CYAN}sudo apt install ffmpeg bc${NC}  ${DIM}(Debian/Ubuntu)${NC}"
    echo -e "    ${CYAN}sudo dnf install ffmpeg bc${NC}  ${DIM}(Fedora)${NC}"
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
  head -c 2 /dev/urandom | xxd -p
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
  read -rp "   Path [$default_path]: " input_path
  SOURCE_DIR="${input_path:-$default_path}"
  SOURCE_DIR="${SOURCE_DIR/#\~/$HOME}"

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
  read -rp "   Path [$default_path]: " input_path
  OUTPUT_DIR="${input_path:-$default_path}"
  OUTPUT_DIR="${OUTPUT_DIR/#\~/$HOME}"

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
  printf "${MAGENTA}│${NC}  ${DIM}Source:${NC}     %-38s  ${MAGENTA}│${NC}\n" "$SOURCE_DIR"
  printf "${MAGENTA}│${NC}  ${DIM}Output:${NC}     %-38s  ${MAGENTA}│${NC}\n" "$OUTPUT_DIR"
  printf "${MAGENTA}│${NC}  ${DIM}Resolution:${NC} %-38s  ${MAGENTA}│${NC}\n" "${WIDTH}x${HEIGHT}"
  if [[ "$BAKE_MODE" == "videos" ]]; then
    printf "${MAGENTA}│${NC}  ${DIM}Duration:${NC}   %-38s  ${MAGENTA}│${NC}\n" "${VIDEO_DURATION}s"
    printf "${MAGENTA}│${NC}  ${DIM}FPS:${NC}        %-38s  ${MAGENTA}│${NC}\n" "$VIDEO_FPS"
    printf "${MAGENTA}│${NC}  ${DIM}Quality:${NC}    %-38s  ${MAGENTA}│${NC}\n" "$quality_text"
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

  if [[ -n "$SOURCE_DIR" || -n "$OUTPUT_DIR" || -n "$TARGET_RES" ]]; then
    INTERACTIVE_MODE=false
  fi
}

validate_cli_args() {
  local has_error=false

  # Default to PWD if not specified
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
      local palette_file="/tmp/palette_$$.png"

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

  if [[ "$BAKE_MODE" == "videos" ]]; then
    process_videos
  else
    process_images
  fi
}

main "$@"
