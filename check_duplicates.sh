#!/bin/bash
#set -x # to debug

# Author: Amauri Casarin Junior
# Purpose: Find and move (optionally) probable duplicate files based on their metadata
# License: GPL-3.0 license
# Version: 0.6
# Date: November 2, 2024

usage_message="Usage: $0 [-sdhc] [-N|M|B|R] target_directory

Options:
        Match operations (any):
        [-s] Perform a metadata match by size in bytes. (default)
        [-d] Perform a metadata match by date (last modification time).
        [-h] Perform a data match by bytes in head and tail.
        [-c] Perform a data match by md5 checksum.

        File operations (one):
        [-N] Files are not touched. (default)
        [-M] Move all duplicates found into target/DUPLICATE subdirectory.
        [-B] Move back files in target/DUPLICATE directory to its origin.
        [-L] Link extra duplicates (replace files for hard links).
        [-R] Remove extra duplicates found keeping just 1 master copy of each match.

        Combinations:
        Match operations can be combined, any combination is valid.
        File operations cannot be combined, only one option is valid.

Example: ./check_duplicates.sh -dcM ~/Documents_directory"

# INITIALIZATION
#--------------------------------------------------------------------------------------
# MATCH FLAGS, CONSTANTS, AND VARIABLES
SIZE_MATCH=true
DATE_MATCH=false
pattern_length=13
HEADTAIL_MATCH=false
CHECKSUM_MATCH=false
headtail_length=10
checksum_length=32
# FILE FLAGS, CONSTANTS, AND VARIABLES
DO_NOTHING=1
MOVE_ALL=0
MOVE_BACK=0
LINK_EXTRAS=0
REMOVE_EXTRAS=0
operation_name=""
#--------------------------------------------------------------------------------------

#INPUT CHECKS
#--------------------------------------------------------------------------------------
# Process options using getopts
while getopts ":sdhcNMBLR" opt; do
    case "$opt" in
        s) SIZE_MATCH=true; pattern_length=13;;

        d) DATE_MATCH=true; pattern_length=46;;

        h) HEADTAIL_MATCH=true; headtail_length=10;;

        c) CHECKSUM_MATCH=true;;


        N) DO_NOTHING=1;;

        M) MOVE_ALL=1; operation_name="move"; DO_NOTHING=0;;

        B) MOVE_BACK=1; operation_name="move"; DO_NOTHING=0;;

        L) LINK_EXTRAS=1; operation_name="link"; DO_NOTHING=0; CHECKSUM_MATCH=true;; # for safety, only allows deletion with checksum match.

        R) REMOVE_EXTRAS=1; operation_name="remove"; DO_NOTHING=0; CHECKSUM_MATCH=true;; # for safety, only allows deletion with checksum match.

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
# Check conflicting file operations
elif [ "$(( DO_NOTHING + MOVE_ALL + MOVE_BACK + LINK_EXTRAS + REMOVE_EXTRAS ))" -gt 1 ]; then
    echo "Error: File operations N, M, B, L or R cannot be used together."
    echo "$usage_message"
    exit 1
elif [ -d "$1" ]; then
    TARGET_DIR="$1"
    # Set inner directory for duplicate files
    DUPLICATES_DIR="$TARGET_DIR/DUPLICATES"
else
    echo "Error: Invalid target directory"
    echo "$usage_message"
    exit 1
fi
#--------------------------------------------------------------------------------------


# SEARCH FUNCTIONS
#--------------------------------------------------------------------------------------
find_duplicates(){
    # METADATA MATCH
    echo -n "Getting metadata... "
    # Find metadata for all files inside the directory
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
}

find_moved() {
    # Find metadata for all files inside the DUPLICATE directory
    MOVED_FILES="$(find "$DUPLICATES_DIR" -type f -printf "%p\n" | sort -n)"
    total_found="$(echo "$MOVED_FILES" | grep -c -v '^$')"

    if [ "$total_found" = 0 ];then
        echo "No files found in $DUPLICATES_DIR."
        exit
    fi

    echo -e "Files found to be moved back:"
    echo "$MOVED_FILES"
    echo -e "Total found: $total_found\n"
}


find_extras() {
    find_duplicates
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
}
#--------------------------------------------------------------------------------------


# FILE OPERATION FUNCTIONS
#--------------------------------------------------------------------------------------
confirm_action() {
    read -p "Are you sure you want to $operation_name those files? [yes/no]: " response
    case "$response" in
        yes) return 0;;
        no) echo "Operation canceled. No files were touched."; exit;;
        *) echo "Invalid response. Please enter 'yes' or 'no'."; confirm_action;;
    esac
}


move_all() {
    confirm_action
    counter=0
    echo -e "\nMoving duplicates..."
    mkdir -p "$DUPLICATES_DIR"  # Create directory if it doesn't exist
    while IFS=$'\t' read -r -a tabs; do
        counter=$((counter + 1))
        formatted_counter=$(printf "%0${#total_duplicates}d" "$counter") # counter with leading zeros
        date="${tabs[-2]}"
        path="${tabs[-1]}"
        relative_path=$(realpath --relative-to="$TARGET_DIR" "$path")
        new_filename="${formatted_counter} {:${relative_path//\//|}"  # Replace / with |
        mv "$path" "${DUPLICATES_DIR}/$new_filename"
        echo "Moved $path to $DUPLICATES_DIR"
    done <<< "$PROBABLE_DUPLICATES"
    echo "ok"
}

move_back () {
    confirm_action
    echo -e "\nMoving files back..."
    while IFS=$'\t' read -r currernt_path; do
        formatted_old_path="${currernt_path#*\{:}"  # Remove everything up to the first '{:'
        old_path="${TARGET_DIR}/${formatted_old_path//\|//}"  # Replace back all '|' with '/'
        mv "$currernt_path" "$old_path"
        echo "Moved to $old_path"
    done <<< "$MOVED_FILES"
    echo "ok"
}

link_extras() {
    confirm_action
    echo -e "\nReplacing extra duplicates by links..."
    while IFS=$'\t' read -r -a tabs; do
        checksum="${tabs[0]}"
        link_path="${tabs[-1]}"
        master_path=$(echo "$MASTER_DUPLICATES" | grep -E "^($checksum)" | awk -F'\t' '{print $NF}')
        ln -Tf "$master_path" "$link_path" # forcing (-f) the link to replace the duplicates
        echo "Replaced "$link_path" by a link to "$master_path""
    done <<< "$EXTRA_DUPLICATES"
    echo "ok"
}

remove_extras() {
    confirm_action
    echo -e "\nRemoving extra duplicates..."
    while IFS=$'\t' read -r -a tabs; do
        path="${tabs[-1]}"
        rm "$path"
        echo "Removed $path"
    done <<< "$EXTRA_DUPLICATES"
    echo "ok"
}
#--------------------------------------------------------------------------------------


# OPERATION:
#--------------------------------------------------------------------------------------
if [ "$DO_NOTHING" = 1 ]; then
    find_duplicates
    exit
elif [ "$MOVE_ALL" = 1 ]; then
    find_duplicates
    move_all
    exit
elif [ "$LINK_EXTRAS" = 1 ]; then
    find_extras
    link_extras
elif [ "$REMOVE_EXTRAS" = 1 ]; then
    find_extras
    remove_extras
    exit
elif [ "$MOVE_BACK" = 1 ]; then
    find_moved
    move_back
    exit
fi
#--------------------------------------------------------------------------------------
