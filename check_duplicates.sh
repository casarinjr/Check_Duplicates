#!/bin/bash

# Author: Amauri Casarin Junior
# Purpose: Find and move (optionally) probable duplicate files based on their metadata
# License: GPL-3.0 license
# Version: 0.1
# Date: October 28, 2024

# Usage example: ./check_duplicates.sh -M ~/Documents_directory

# Initialize flag
MOVE_ALL=false

# Process options using getopts
while getopts ":M" opt; do
    case "$opt" in
        M) MOVE_ALL=true;;
        \?) echo -e "Invalid option: -$OPTARG. \nUse -M if you want to move all duplicate files" >&2; exit 1;;
    esac
done

# Shift to remove processed options
shift $((OPTIND - 1))


# Check if the correct number of arguments is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 [-M] target_directory "
    exit 1
fi


# Directory from command-line argument
TARGET_DIR="$1"
# Set inner directory for duplicate files
DUPLICATES_DIR="$TARGET_DIR/DUPLICATES"


echo -n "Searching target files... "
# Find metada for all files inside the directory
TARGET_FILES="$(find "$TARGET_DIR" -type f -printf "%13s\t%T+\t%p\n" | sort -n)"
echo "ok"


echo -n "Matching metada-duplicate files... "
# Check BASIC METADA (same size and last modification time)
META_DUPLICATES="$(uniq -D -w 46 <<< "$TARGET_FILES")"
DUPLICATES_COUNT="$(echo "$META_DUPLICATES" | uniq -c -w 46)"
echo "ok"
echo -e "\nDuplicate files:"
echo "$META_DUPLICATES"
echo -e "Total found: $(echo "$DUPLICATES_COUNT" | grep -c -v '^$')"

# PROCESS MOVE FILES
if [ "$MOVE_ALL" = true ]; then
    echo -n "Moving files..."
    mkdir -p "$DUPLICATES_DIR"  # Create directory if it doesn't exist
    while IFS=$'\t' read -r size date path; do
        relative_path=$(realpath --relative-to="$TARGET_DIR" "$path")
        mv "$path" "${DUPLICATES_DIR}/${date}_${relative_path//\//_}}" # Replace slashes with underscores
        echo "Moved duplicate: $path to $DUPLICATES_DIR"
    done <<< "$META_DUPLICATES"
    echo "ok"
fi
