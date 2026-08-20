#!/bin/bash

# 1. Get current hour (01-12)
hour=$(date +%I)

# 2. Get time strictly (No spaces: 03:33:06AM)
time_text=$(date "+%I:%M:%S%p")

# 3. Icon Map
case $hour in
    "00"|"12") icon="󱑊" ;; # 12
    "01")      icon="󱐿" ;; # 1
    "02")      icon="󱑀" ;; # 2
    "03")      icon="󱑁" ;; # 3 
    "04")      icon="󱑂" ;; # 4 
    "05")      icon="󱑃" ;; # 5
    "06")      icon="󱑄" ;; # 6
    "07")      icon="󱑅" ;; # 7
    "08")      icon="󱑆" ;; # 8
    "09")      icon="󱑇" ;; # 9
    "10")      icon="󱑈" ;; # 10
    "11")      icon="󱑉" ;; # 11
    *)         icon="󰗎" ;; # Error fallback
esac

# 4. Output: Icon + Space + Time
echo "$icon $time_text"