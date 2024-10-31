#!/bin/bash
#set -x # to debug

# Author: Amauri Casarin Junior
# Purpose: Find and move (optionally) probable duplicate files based on their metadata
# License: GPL-3.0 license
# Version: 0.4
# Date: October 31, 2024

usage_message="Usage: $0 [-sdhc] [-N|M|R] target_directory

Options:
        Match operations (any):
        [-s] Perform a metadata match by size in bytes. (default)
        [-d] Perform a metadata match by date (last modification time).
        [-h] Perform a data match by bytes in head and tail.
        [-c] Perform a data match by md5 checksum.

        File operations (one):
        [-N] Files are not touched. (default)
        [-M] Move all duplicates found into a subdirectory.
        [-R] Remove extra duplicates found (keep 1 master copy).

        Combinations:
        Match operations can be combined, any combination is valid.
        File operations cannot be combined, only one option is valid.

Example: ./check_duplicates.sh -dcM ~/Documents_directory"


# METADA FLAGS
SIZE_MATCH=true
DATE_MATCH=false
pattern_length=13
# DATA FLAGS
HEADTAIL_MATCH=false
CHECKSUM_MATCH=false
headtail_length=10
checksum_length=32
# FILE FLAGS
DO_NOTHING=1
MOVE_ALL=0
REMOVE_EXTRAS=0
FILE_OPERATION=""

# Process options using getopts
while getopts ":sdhcNMR" opt; do
    case "$opt" in
        s) SIZE_MATCH=true; pattern_length=13;;

        d) DATE_MATCH=true; pattern_length=46;;

        h) HEADTAIL_MATCH=true; headtail_length=10;;

        c) CHECKSUM_MATCH=true;;

        N) DO_NOTHING=1;;

        M) MOVE_ALL=1; FILE_OPERATION="move"; DO_NOTHING=0;;

        R) REMOVE_EXTRAS=1; FILE_OPERATION="remove"; DO_NOTHING=0; CHECKSUM_MATCH=true;; # for safety, only allows deletion with checksum match.

        \?) echo -e "Invalid option: -$OPTARG"; echo "$usage_message"; exit 1;;
    esac
done
# Shift to remove processed options
shift $((OPTIND - 1))


# Check the correct number of arguments
if [ "$#" -ne 1 ]; then
    echo "Error: Invalid number of arguments."
    echo "$usage_message"
    exit 1
# Check conflicts with file operations
elif [ "$(( DO_NOTHING + MOVE_ALL + REMOVE_EXTRAS ))" -gt 1 ]; then
    echo "Error: Options -N,-M or -R cannot be used together."
    echo "$usage_message"
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


# Function to prompt for confirmation
confirm_action() {
    read -p "Are you sure you want to $FILE_OPERATION those files? [yes/no]: " response
    case "$response" in
        yes) return 0;;
        no) echo "Operation canceled. No files were touched."; exit;;
        *) echo "Invalid response. Please enter 'yes' or 'no'."; confirm_action;;
    esac
}



# FILE OPERATIONS
if [ "$MOVE_ALL" = 1 ]; then
    confirm_action
    counter=0
    echo "$leading_zeros"
    echo -e "\nMoving duplicates..."
    mkdir -p "$DUPLICATES_DIR"  # Create directory if it doesn't exist
    while IFS=$'\t' read -r -a tabs; do
        counter=$((counter + 1))
        formatted_counter=$(printf "%0${#total_duplicates}d" "$counter") # with leeding zeros
        date="${tabs[-2]}"
        path="${tabs[-1]}"
        relative_path=$(realpath --relative-to="$TARGET_DIR" "$path")
        new_filename="${formatted_counter} {${relative_path//\//|}}"  # Replace / with |
        mv "$path" "${DUPLICATES_DIR}/$new_filename"
        echo "Moved $path to $DUPLICATES_DIR"
    done <<< "$PROBABLE_DUPLICATES"
    echo "ok"

elif [ "$REMOVE_EXTRAS" = 1 ]; then
    # Selecting master and extra files
    MASTER_DUPLICATES="$(echo "$PROBABLE_DUPLICATES" | uniq -w $checksum_length)"
    total_keep="$(echo "$MASTER_DUPLICATES" | grep -c -v '^$')"
    EXTRA_DUPLICATES="$(echo "$PROBABLE_DUPLICATES" | grep -v -x "$MASTER_DUPLICATES")"
    total_remove="$(echo "$EXTRA_DUPLICATES" | grep -c -v '^$')"

    echo -e "Master duplicate files to be kept:"
    echo "$MASTER_DUPLICATES"
    echo -e "Total: $total_keep"
    echo -e "\nExtra duplicate files to be removed:"
    echo "$EXTRA_DUPLICATES"
    echo -e "Total: $total_remove"

    confirm_action
    echo -e "\nRemoving files..."
    while IFS=$'\t' read -r -a tabs; do
        path="${tabs[-1]}"
        rm "$path"
        echo "Removed $path"
    done <<< "$EXTRA_DUPLICATES"
    echo "ok"
fi
