#!/bin/bash

# Author: Amauri Casarin Junior
# Purpose: Find and move (optionally) probable duplicate files based on their metadata
# License: GPL-3.0 license
# Version: 0.7
# Date: November 2, 2024

usage_message="Usage: $0 [-isdhc] [-N|M|B|R] target_directory

Options:
        Match operations (any):
        [-i] Perform a metada match by inode (find hard links).
        [-s] Perform a metadata match by size in bytes. (default)
        [-d] Perform a metadata match by date (last modification time).
        [-h] Perform a data match by bytes in head and tail.
        [-c] Perform a data match by md5

        File operations (one):
        [-N] Files are not touched. (default)
        [-M] Move all duplicates found into target/DUPLICATE subdirectory.
        [-B] Move back files in target/DUPLICATE directory to its origin.
        [-L] Link extra duplicates (replace files for hard links).
        [-R] Remove extra duplicates found keeping just 1 master copy of each match.

        Combinations:
        Match operations can be combined, any combination is valid.
        File operations cannot be combined, only one option is valid.

Example: ./check_duplicates.sh -dcM ~/Documents"

# INITIALIZATION
#--------------------------------------------------------------------------------------
# MATCH FLAGS
SIZE_MATCH=true
INODE_MATCH=false
DATE_MATCH=false
HEADTAIL_MATCH=false
CHECKSUM_MATCH=false
# FILE FLAGS AND VARIABLES
DO_NOTHING=1
MOVE_ALL=0
MOVE_BACK=0
LINK_EXTRAS=0
REMOVE_EXTRAS=0

#--------------------------------------------------------------------------------------

#INPUT CHECKS
#--------------------------------------------------------------------------------------
# Process options using getopts
while getopts ":sdihcNMBLR" opt; do
    case "$opt" in
        s) SIZE_MATCH=true;;

        d) DATE_MATCH=true;;

        i) INODE_MATCH=true;;

        h) HEADTAIL_MATCH=true; headtail_length=10;;

        c) CHECKSUM_MATCH=true;;


        N) DO_NOTHING=1;;

        M) MOVE_ALL=1; operation_name="move"; DO_NOTHING=0;;

        B) MOVE_BACK=1; operation_name="move back"; DO_NOTHING=0;;

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
find_all() {
    echo -n "Getting metadata... "
    # Find metadata for all files inside the directory
    # fields: 1(size) 2(date) 3(headtail) 4(checksum) 5(inode) 6(path)
    fields=6
    TARGET_FILES="$(find "$TARGET_DIR" -type f -printf "%s\t%T+\t-\t-\t%i\t%p\n")"
    total_target="$(echo "$TARGET_FILES" | grep -c -v '^$')"

    echo "ok"
}


find_duplicates() {
    DUPLICATES=$(awk -F'\t' -v cols="${match_columns[*]}" '
    BEGIN {
        split(cols, colsArr, " ")
    }
    { # process each column from the array received into a combined key
        key = ""
        for (i in colsArr) {
            if (key != "")
                key = key "\t"
            key = key $colsArr[i]
        }
        count[key]++
        if (lines[key])
            lines[key] = lines[key] "\n" $0 # Append to existing entry
        else
            lines[key] = $0 # Initialize new entry
    }
    END {
        for (key in count)
            if (count[key] > 1) # Check for duplicates
                print lines[key] # Print duplicate lines
    }' <<< "$1" )
    total_duplicates="$(echo "$DUPLICATES" | grep -c -v '^$')"
    if [ "$total_duplicates" = 0 ];then
        echo "$total_target files assessed. No duplicate files found for your criteria."
        exit
    else
        TARGET_FILES=$DUPLICATES #update the tarfet with the duplicates for each match operation
        echo -e "Step duplicate files: $total_duplicates"
        #echo "$DUPLICATES"
    fi
}

find_extras() {
    MASTER_DUPLICATES=$(awk -F'\t' -v cols="${match_columns[*]}" '
    BEGIN {
        split(cols, colsArr, " ")
    }
    {
        # process each column from the array received into a combined key
        key = ""
        for (i in colsArr) {
            if (key != "")
                key = key "\t"
            key = key $colsArr[i]
        }
        if (!seen[key]++) { # finds masters (1 element of each key match)
            print
        }
    }' <<< "$TARGET_FILES")
    total_keep="$(echo "$MASTER_DUPLICATES" | grep -c -v '^$')"
    EXTRA_DUPLICATES="$(echo "$DUPLICATES" | grep -v -x "$MASTER_DUPLICATES")"
    total_remove="$(echo "$EXTRA_DUPLICATES" | grep -c -v '^$')"

    echo -e "\nMaster duplicate files to be kept:"
    echo "$MASTER_DUPLICATES"
    echo -e "Total: $total_keep"
    echo -e "\nExtra duplicate files to be removed:"
    echo "$EXTRA_DUPLICATES"
    echo -e "Total: $total_remove"
}


find_matches() {
    # METADATA MATCH
    match_columns=()
    if [ "$SIZE_MATCH" = true ];then
        match_columns+=("1")
        find_duplicates "$TARGET_FILES"
    fi

    if [ "$DATE_MATCH" = true ];then
        match_columns+=("2")
        find_duplicates "$TARGET_FILES"
    fi

    if [ "$INODE_MATCH" = true ];then
        match_columns+=("5")
        find_duplicates "$TARGET_FILES"
    fi


    # HEADTAIL-DATA MATCH
    if [ "$HEADTAIL_MATCH" = true ];then
        match_columns+=("3")
        target_update=''
        counter=0
        while IFS=$'\t' read -r size date headtail checksum inode path; do
            counter=$((counter + 1))
            printf "\rGetting headtail-data... %d/%d " "$counter" "$total_duplicates"
            HEAD="$(head -c $headtail_length "$path" | xxd -p)"
            TAIL="$(tail -c $headtail_length "$path" | xxd -p)"
            headtail="${HEAD}${TAIL}"
            target_update+="$size\t$date\t$headtail\t$checksum\t$inode\t$path\n" #update with the headtail data,change to printf
        done <<< "$TARGET_FILES"
        echo -e "ok"
        TARGET_FILES="$(echo -e "$target_update")"
        find_duplicates "$TARGET_FILES" "${match_columns[*]}"
    fi

    # CHECKSUM-DATA MATCH
    if [ "$CHECKSUM_MATCH" = true ];then
        match_columns+=("4")
        target_update=''
        counter=0
        while IFS=$'\t' read -r size date headtail checksum inode path; do
            counter=$((counter + 1))
            printf "\rGetting checksum data... %d/%d " "$counter" "$total_duplicates"
            checksum=$(md5sum "$path"| cut -f 1  -d " ")
            target_update+="$size\t$date\t$headtail\t$checksum\t$inode\t$path\n" #update with the checksum data
        done <<< "$TARGET_FILES"
        echo -e "ok"
        TARGET_FILES="$(echo -e "$target_update")"
        find_duplicates "$TARGET_FILES" "${match_columns[*]}"
    fi


    echo -e "\nDuplicate files found:"
    echo "$DUPLICATES" | sort -n
    echo -e "$total_target files assessed. $total_duplicates duplicates found."
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
    echo -e "Total: $total_found\n"
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
    done <<< "$TARGET_FILES"
    echo "ok"
}

move_back () {
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
    find_all
    find_matches
    exit
elif [ "$MOVE_ALL" = 1 ]; then
    find_all
    find_matches
    confirm_action
    move_all
    exit
elif [ "$LINK_EXTRAS" = 1 ]; then
    find_all
    find_matches
    find_extras
    confirm_action
    link_extras
    exit
elif [ "$REMOVE_EXTRAS" = 1 ]; then
    find_all
    find_matches
    find_extras
    confirm_action
    remove_extras
    exit
elif [ "$MOVE_BACK" = 1 ]; then
    find_moved
    confirm_action
    move_back
    exit
fi
#--------------------------------------------------------------------------------------
