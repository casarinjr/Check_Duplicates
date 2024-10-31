#!/bin/bash
#set -x # to debug

# Author: Amauri Casarin Junior
# Purpose: Find and move (optionally) probable duplicate files based on their metadata
# License: GPL-3.0 license
# Version: 0.3
# Date: October 30, 2024

# Example: ./check_duplicates.sh -dhcM ~/Documents_directory

# METADA FLAGS
SIZE_MATCH=true
DATE_MATCH=false
pattern_length=13
# DATA FLAGS
HEADTAIL_MATCH=false
CHECKSUM_MATCH=false
headtail_length=10
# FILE FLAGS
MOVE_ALL=false


# Process options using getopts
while getopts ":sdhcM" opt; do
    case "$opt" in
        s) SIZE_MATCH=true; pattern_length=13;;

        d) DATE_MATCH=true; pattern_length=46;;

        h) HEADTAIL_MATCH=true; headtail_length=10;;

        c) CHECKSUM_MATCH=true; checksum_length=32;;

        M) MOVE_ALL=true;;
        \?) echo -e "Invalid option: -$OPTARG.
Options:
        [-s] Perform a metada match by size in bytes. (default)
        [-d] Perform a metada match by date (last modification time).
        [-h] Perform a data match by bytes in head and tail.
        [-c] Perform a data match by md5 checksum.
        [-M] Move all duplicates found into a subdirectory." >&2; exit 1;;
    esac
done

# Shift to remove processed options
shift $((OPTIND - 1))


# Check if the correct number of arguments is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 [-sdhcM] target_directory "
    exit 1
fi


# Directory from command-line argument
TARGET_DIR="$1"
# Set inner directory for duplicate files
DUPLICATES_DIR="$TARGET_DIR/DUPLICATES"


# METADATA MATCH
echo -n "Getting metada... "
# Find metada for all files inside the directory
TARGET_FILES="$(find "$TARGET_DIR" -type f -printf "%13s\t%T+\t%p\n" | sort -n)"
META_DUPLICATES="$(uniq -D -w $pattern_length <<< "$TARGET_FILES")"
echo "ok"
# Update probable duplicates
PROBABLE_DUPLICATES=$META_DUPLICATES
total_duplicates="$(echo "$PROBABLE_DUPLICATES" | grep -c -v '^$')"
if [ "$total_duplicates" = 0 ];then
    echo "No duplicate files found."
    exit
fi

echo -e "Metadata duplicate files:"
echo "$PROBABLE_DUPLICATES"
echo -e "Total found: $total_duplicates\n"


# HEADTAIL-DATA MATCH
if [ "$HEADTAIL_MATCH" = true ];then
    counter=0
    while IFS=$'\t' read -r -a tabs; do
        counter=$((counter + 1))
        size="${tabs[-3]}"
        date="${tabs[-2]}"
        path="${tabs[-1]}"
        printf "\rGetting headtail-data... %d/%d " "$counter" "$total_duplicates"
        HEAD="$(head -c $headtail_length "$path" | xxd -p)"
        TAIL="$(tail -c $headtail_length "$path" | xxd -p)"
        headtail="${HEAD}${TAIL}"
        headtails+="$headtail\t$size\t$date\t$path\n"
    done <<< "$PROBABLE_DUPLICATES"
    echo -e "ok"
    HEADTAIL_DUPLICATES="$(echo -e "$headtails" | sort -n | uniq -D -w $((4 * headtail_length)) | awk 'NF')"
    PROBABLE_DUPLICATES=$HEADTAIL_DUPLICATES # Update probable duplicates
    total_duplicates="$(echo "$PROBABLE_DUPLICATES" | grep -c -v '^$')"
    if [ "$total_duplicates" = 0 ];then
        echo "No duplicate files found."
        exit
    fi
    echo -e "Headtail duplicate files:"
    echo "$PROBABLE_DUPLICATES"
    echo -e "Total found: $total_duplicates\n"
fi

# CHECKSUM-DATA MATCH
if [ "$CHECKSUM_MATCH" = true ];then
    counter=0
    while IFS=$'\t' read -r -a tabs; do
        counter=$((counter + 1))
        size="${tabs[-3]}"
        date="${tabs[-2]}"
        path="${tabs[-1]}"
        printf "\rGetting checksum data... %d/%d " "$counter" "$total_duplicates"
        checksum=$(md5sum "$path"| cut -f 1  -d " ")
        checksums+="$checksum\t$size\t$date\t$path\n"
    done <<< "$PROBABLE_DUPLICATES"
    echo -e "ok"
    CHECKSUM_DUPLICATES="$(echo -e "$checksums" | sort -n | uniq -D -w $checksum_length)"
    PROBABLE_DUPLICATES=$CHECKSUM_DUPLICATES # Update probable duplicates
    total_duplicates="$(echo "$PROBABLE_DUPLICATES" | grep -c -v '^$')"
    if [ "$total_duplicates" = 0 ];then
        echo "No duplicate files found."
        exit
    fi
    echo -e "Checksum duplicate files:"
    echo "$PROBABLE_DUPLICATES"
    echo -e "Total found: $total_duplicates\n"
fi



# PROCESS MOVE FILES
if [ "$MOVE_ALL" = true ]; then
    echo -e "\nMoving duplicates..."
    mkdir -p "$DUPLICATES_DIR"  # Create directory if it doesn't exist
    while IFS=$'\t' read -r -a tabs; do
        counter=$((counter + 1))
        date="${tabs[-2]}"
        path="${tabs[-1]}"
        relative_path=$(realpath --relative-to="$TARGET_DIR" "$path")
        mv "$path" "${DUPLICATES_DIR}/${date}_${relative_path//\//_}}" # Replace slashes with underscores
        echo "Moved $path to $DUPLICATES_DIR"
    done <<< "$PROBABLE_DUPLICATES"
    echo "ok"
fi
