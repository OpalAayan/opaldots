#!/usr/bin/env bash

FUZZEL_MENU="$HOME/.config/fuzzel/scripts/powermenu.sh"
ROFI_MENU="$HOME/.config/rofi/scripts/powermenu.sh"

# ==========================================
# PHASE 1: TRNG (Harvesting Human Entropy)
# ==========================================

# 1. Grab Mouse Coordinates (Fallback to PID if Wayland denies us)
COORDS=$(hyprctl cursorpos 2>/dev/null)
if [ -z "$COORDS" ]; then
  X=$$
  Y=$$
else
  X=$(echo "$COORDS" | cut -d',' -f1)
  Y=$(echo "$COORDS" | cut -d',' -f2 | tr -d ' ')
fi

# 2. Grab Nanosecond Time and Process ID
T=$(date +%N)
PID=$$

# ==========================================
# PHASE 2: The Balatro Pre-Hash
# ==========================================

# We feed the physical data into awk to calculate the Balatro float math.
# We also inject the PID. We extract a massive integer to use as our seed.
BALATRO_SEED=$(awk -v x="$X" -v y="$Y" -v t="$T" -v p="$PID" '
BEGIN {
    # Balatro logic + PID perturbation
    raw_val = (x * 0.33411983) + (y * 0.874146) + (t * 0.000000412311010) + (p * 0.1984)
    
    # Multiply by 100,000 to eliminate decimals, print as a raw whole number
    printf "%.0f", raw_val * 100000
}')

# Ensure the seed fits safely within a 32-bit integer space for bash math
SAFE_SEED=$((BALATRO_SEED % 2147483648))

# ==========================================
# PHASE 3: PRNG (The Cryptographic Scramble)
# ==========================================

# 1. Linear Congruential Generator (LCG)
A=1103515245
C=12345
M=2147483648

LCG_VAL=$(((A * SAFE_SEED + C) % M))

# 2. Xorshift (Bitwise Avalanche)
LCG_VAL=$((LCG_VAL ^ (LCG_VAL >> 13)))
LCG_VAL=$((LCG_VAL ^ (LCG_VAL << 17)))
LCG_VAL=$((LCG_VAL ^ (LCG_VAL >> 5)))

# ==========================================
# PHASE 4: The Final Collapse
# ==========================================

# Extract the 16th bit (deep in the scrambled stack) and isolate it
DECISION=$(((LCG_VAL >> 16) & 1))

# Execute based on the chaotic bit
if [ "$DECISION" -eq 0 ]; then
  exec "$FUZZEL_MENU"
else
  exec "$ROFI_MENU"
fi
