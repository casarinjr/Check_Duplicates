#!/bin/bash

# Author: Amauri Casarin Junior
# Purpose: Find and move (optionally) probable duplicate files based on their metadata
# License: GPL-3.0 license
# Version: 0.2
# Date: October 29, 2024

# Example: ./check_duplicates.sh -M ~/Documents_directory

# METADA FLAGS
SIZE_MATCH=true
DATE_MATCH=false
pattern_length=13
# DATA FLAGS
HEADTAIL_MATCH=true
headtail_length=10
# FILE FLAGS
MOVE_ALL=false


# Process options using getopts
while getopts ":shdM" opt; do
    case "$opt" in
        s) SIZE_MATCH=true; pattern_length=13;;

        d) DATE_MATCH=true; pattern_length=46;;

        h) HEADTAIL_MATCH=true; headtail_length=10;;

        M) MOVE_ALL=true;;
        \?) echo -e "Invalid option: -$OPTARG." >&2; exit 1;;
    esac
done

# Shift to remove processed options
shift $((OPTIND - 1))


# Check if the correct number of arguments is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 [-d] [-M] target_directory "
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
META_DUPLICATES="$(uniq -D -w $pattern_length <<< "$TARGET_FILES")"
echo "ok"
echo -e "\nMetadata duplicate files:"
echo "$META_DUPLICATES"
total_meta_duplicates="$(echo "$META_DUPLICATES" | grep -c -v '^$')"
echo -e "Total found: $total_meta_duplicates\n"


counter=0
while IFS=$'\t' read -r size date path; do
    counter=$((counter + 1))
    printf "\rChecking headtail-data... %d/%d" "$counter" "$total_meta_duplicates"
    HEAD="$(head -c $headtail_length "$path" | xxd -p)"
    TAIL="$(tail -c $headtail_length "$path" | xxd -p)"
    headtail="${HEAD}${TAIL}"
    headtails=$(echo -e "$headtails\n$headtail\t$size\t$date\t$path")
done <<< "$META_DUPLICATES"

echo -e "\nHeadtail duplicate files:"
HEADTAIL_DUPLICATES="$(echo "$headtails" | sort -n | uniq -D -w $((4 * headtail_length)))"
echo "$HEADTAIL_DUPLICATES"
echo "Total found: $(echo "$HEADTAIL_DUPLICATES" | grep -c -v '^$')"


# PROCESS MOVE FILES
if [ "$MOVE_ALL" = true ]; then
    echo -e "\nMoving files..."
    mkdir -p "$DUPLICATES_DIR"  # Create directory if it doesn't exist
    while IFS=$'\t' read -r headtail size date path; do
        relative_path=$(realpath --relative-to="$TARGET_DIR" "$path")
        mv "$path" "${DUPLICATES_DIR}/${date}_${relative_path//\//_}}" # Replace slashes with underscores
        echo "Moved duplicate: $path to $DUPLICATES_DIR"
    done <<< "$HEADTAIL_DUPLICATES"
    echo "ok"
fi
