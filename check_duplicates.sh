#!/bin/bash

# Author: Amauri Casarin Junior
# Purpose: Find and move (optionally) probable duplicate files based on their metadata
# License: GPL-3.0 license
# Version: 0.8
# Date: November 3, 2024

usage_message="Usage: $0 [-options] target_directory

Options:
        Search operations (one):
        [-r] Recursive search in target directory and all its subdirectories. (default)
        [-d:] Maximum depth of search. Requires any number ≥ 1.

        Match operations (any):
        [-i] Perform a metadata match by inode (find hard links).
        [-s] Perform a metadata match by size in bytes. (default)
        [-t] Perform a metadata match by last modified time.
        [-h] Perform a data match by 10 bytes in head and tail.
        [-c] Perform a data match by md5 checksum.

        File operations (one):
        [-N] Files are not touched. (default)
        [-M] Move all duplicates found into target/DUPLICATE subdirectory.
        [-B] Move back files in target/DUPLICATE directory to its origin.
        [-L] Link extra duplicates (replace files by hard links).
        [-R] Remove extra duplicates found, keeping just 1 master copy of each match.

        Output verbosity:
        [-q] Quiet: only status and operational messages are echoed in the terminal. (0 precedence)
        [-n] Normal: final results are echoed additionally. (1 precedence) (default)
        [-v] Verbose: partial results (of each matching process) are echoed additionally. (2 precedence)


        Combinations:
        Search operations cannot be combined, only one option is valid.
        Match operations can be combined, any combination is valid.
        File operations cannot be combined, only one option is valid.
        If combined, the higher output verbosity will take precedent.

Example: ./check_duplicates.sh -tcM ~/Documents"

# INITIALIZATION
#--------------------------------------------------------------------------------------
# SEARCH FLAGS
RECURSIVE_SEARCH=1
DEPTH_SEARCH=0
# MATCH FLAGS
SIZE_MATCH=true
INODE_MATCH=false
TIME_MATCH=false
HEADTAIL_MATCH=false
CHECKSUM_MATCH=false
# FILE FLAGS
DO_NOTHING=1
MOVE_ALL=0
MOVE_BACK=0
LINK_EXTRAS=0
REMOVE_EXTRAS=0
# OUTPUT VARIABLES
verbosity=1 # 0 quiet, 1 normal and 2 verbose.
#--------------------------------------------------------------------------------------

#INPUT CHECKS
#--------------------------------------------------------------------------------------
# Process options using getopts
while getopts ":rd:qnvstihcNMBLR" opt; do
    case "$opt" in
        r) RECURSIVE_SEARCH=1;;

        d) DEPTH_SEARCH=1; max_depth=${OPTARG}; RECURSIVE_SEARCH=0;;

        q) verbosity=0;;

        n) verbosity=1;;

        v) verbosity=2 ;;


        s) SIZE_MATCH=true;;

        t) TIME_MATCH=true;;

        i) INODE_MATCH=true;;

        h) HEADTAIL_MATCH=true; headtail_length=10;;

        c) CHECKSUM_MATCH=true;;


        N) DO_NOTHING=1;;

        M) MOVE_ALL=1; operation_name="move"; DO_NOTHING=0;;

        B) MOVE_BACK=1; operation_name="move back"; DO_NOTHING=0;;

        L) LINK_EXTRAS=1; operation_name="link"; DO_NOTHING=0; CHECKSUM_MATCH=true;; # for safety, only allows deletion with checksum match.

        R) REMOVE_EXTRAS=1; operation_name="remove"; DO_NOTHING=0; CHECKSUM_MATCH=true;; # for safety, only allows deletion with checksum match.


        \?) echo -e "Invalid option: -$OPTARG"; echo "$usage_message"; exit 1;;

        :) echo "Option -$OPTARG requires an argument."
    esac
done
# Shift to remove processed options
shift $((OPTIND - 1))


# Check the correct number of arguments
if [ "$#" -ne 1 ]; then
     echo "Error: Invalid number of arguments."
     echo "$usage_message"
     exit 1
# Check conflicting search operations
elif [ "$(( RECURSIVE_SEARCH + DEPTH_SEARCH ))" -gt 1 ]; then
    echo "Error: Search operations -r and -d cannot be used together."
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

# Function to handle verbosity
log() {
    local message_type="$1"
    # Capture echo options:
    if [ $# -eq 3 ]; then
        local echo_option="$2"
        local message="$3"
    else
        local echo_option=""
        local message="$2"
    fi

    # Echo message by verbosity level
    if [ "$verbosity" = 0 ] && [ "$message_type" = "status" ]; then
        echo "$echo_option" "$message"
    elif  [ "$verbosity" = 1 ] && [[ "$message_type" =~ ^(status|final)$ ]]; then
        echo "$echo_option" "$message"
    elif  [ "$verbosity" = 2 ] && [[ "$message_type" =~ ^(status|partial|final)$ ]]; then
        echo "$echo_option" "$message"
    fi
}

# SEARCH FUNCTIONS
#--------------------------------------------------------------------------------------
search_files() {
    log status -n "Searching files... "
    # Find metadata for all files inside the directory
    # fields: 1(size) 2(time) 3(headtail) 4(checksum) 5(inode) 6(path)
    duplicates_header="$(echo -e "Size\tTime\tHeadtail\tChecksum\tInode\tPath")"
    if [ "$DEPTH_SEARCH" = 1 ]; then
        TARGET_FILES="$(find "$TARGET_DIR" -maxdepth "$max_depth" -type f -size +0c -printf "%s\t%T+\t-\t-\t%i\t%p\n")"
    else
        TARGET_FILES="$(find "$TARGET_DIR" -type f -size +0c -printf "%s\t%T+\t-\t-\t%i\t%p\n")"
    fi
    total_target="$(echo "$TARGET_FILES" | grep -c -v '^$')"
    log status "ok"
    log status -e "Found files in $TARGET_DIR: $total_target\n"
}


find_duplicates() {
    match_name="$2"
    log status -E "Matching for $match_name..."
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
        log status -e "No duplicate files found for your criteria."
        exit
    else
        TARGET_FILES=$DUPLICATES #update the target with the duplicates for each match operation
        log partial -E "$DUPLICATES" | sort -n
        log status -E "Found $match_name-duplicates: $total_duplicates"
        log partial ""
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

    log status -e "\nMaster duplicate files to be kept:"
    log final -E "$MASTER_DUPLICATES"
    log status -e "Total: $total_keep"
    log final ""
    log status -e "Extra duplicate files to be removed:"
    log final -E "$EXTRA_DUPLICATES"
    log status -e "Total: $total_remove"

    master_duplicates_file="$TARGET_DIR/CDreport_master_duplicates.txt"
    extra_duplicates_file="$TARGET_DIR/CDreport_extra_duplicates.txt"
    echo "$duplicates_header" > $master_duplicates_file
    echo "$duplicates_header" > $extra_duplicates_file
    echo "$MASTER_DUPLICATES" >> $master_duplicates_file
    echo "$EXTRA_DUPLICATES" >> $extra_duplicates_file
    log status -e "\nMaster duplicates report saved to $master_duplicates_file"
    log status -e "Extra duplicates report saved to $extra_duplicates_file"
}


find_matches() {
    # METADATA MATCH
    match_columns=()
    if [ "$INODE_MATCH" = true ];then
        match_columns+=("5")
        find_duplicates "$TARGET_FILES" "inode"
    else
        # Discard hard links (keep just one)
        log status -E "Discarding hardlinked files"
        DUPLICATES="$(awk -F'\t' '!seen[$5]++' <<< "$TARGET_FILES")"
        TARGET_FILES=$DUPLICATES #update the target
    fi

    if [ "$SIZE_MATCH" = true ];then
        match_columns+=("1")
        find_duplicates "$TARGET_FILES" "size"
    fi

    if [ "$TIME_MATCH" = true ];then
        match_columns+=("2")
        find_duplicates "$TARGET_FILES" "time"
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
        find_duplicates "$TARGET_FILES" "headtail"
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
        find_duplicates "$TARGET_FILES" "checksum"
    fi

    DUPLICATES="$(echo "$DUPLICATES" | sort -n)"
    log status -e "\nResults:"
    log final -E "$DUPLICATES"
    log status -e "$total_target files assessed. $total_duplicates duplicates found."

    duplicates_file="$TARGET_DIR/CDreport_duplicates.txt"
    echo "$duplicates_header" > $duplicates_file
    echo "$DUPLICATES" >> $duplicates_file
    log status -e "\nDuplicates report saved to $duplicates_file"
}

search_moved() {
    # Find metadata for all files inside the DUPLICATE directory
    MOVED_FILES="$(find "$DUPLICATES_DIR" -type f -printf "%p\n" | sort -n)"
    total_found="$(echo "$MOVED_FILES" | grep -c -v '^$')"

    if [ "$total_found" = 0 ];then
        log status "No files found in $DUPLICATES_DIR."
        exit
    fi

    log status -e "Files found to be moved back:"
    log partial -E "$MOVED_FILES"
    log status -e "Total: $total_found\n"

    moved_found="$TARGET_DIR/CDreport_moved_found.txt"
    echo "$MOVED_FILES" > $moved_found
    log status -e "\nMoved files found report saved to $moved_found"
}

#--------------------------------------------------------------------------------------


# FILE OPERATION FUNCTIONS
#--------------------------------------------------------------------------------------
confirm_action() {
    echo ""
    read -p "Are you sure you want to $operation_name those files? [yes/no]: " response
    case "$response" in
        yes) return 0;;
        no) echo "Operation canceled. No files were touched."; exit;;
        *) echo "Invalid response. Please enter 'yes' or 'no'."; confirm_action;;
    esac
}


move_all() {
    counter=0
    mkdir -p "$DUPLICATES_DIR"  # Create directory if it doesn't exist
    log status -en "\nMoving duplicates..."
    moved_files="$TARGET_DIR/CDreport_moved_files.txt"
    echo -n "" > $moved_files
    while IFS=$'\t' read -r -a tabs; do
        counter=$((counter + 1))
        formatted_counter=$(printf "%0${#total_duplicates}d" "$counter") # counter with leading zeros
        date="${tabs[-2]}"
        path="${tabs[-1]}"
        relative_path=$(realpath --relative-to="$TARGET_DIR" "$path")
        new_filename="${formatted_counter} {:${relative_path//\//|}"  # Replace / with |
        mv "$path" "${DUPLICATES_DIR}/$new_filename"
        report_line="Moved $path to $DUPLICATES_DIR"
        log partial "$report_line"
        echo "$report_line" >> $moved_files
    done <<< "$TARGET_FILES"
    log status "ok"
    log status -e "\nMoved files report saved to $moved_files"
}

move_back () {
    log status -en "\nMoving files back..."
    movedback_files="$TARGET_DIR/CDreport_movedback_files.txt"
    echo -n "" > $movedback_files
    while IFS=$'\t' read -r currernt_path; do
        formatted_old_path="${currernt_path#*\{:}"  # Remove everything up to the first '{:'
        old_path="${TARGET_DIR}/${formatted_old_path//\|//}"  # Replace back all '|' with '/'
        mv "$currernt_path" "$old_path"
        report_line="Moved back to $old_path"
        log partial "$report_line"
        echo "$report_line" >> $movedback_files
    done <<< "$MOVED_FILES"
    log status -E "ok"
    log status -e "\nMoved back files report saved to $movedback_files"
}

link_extras() {
    log status  -en "\nReplacing extra duplicates by hard links..."
    linked_files="$TARGET_DIR/CDreport_linked_files.txt"
    echo -n "" > $linked_files
    while IFS=$'\t' read -r -a tabs; do
        checksum="${tabs[0]}"
        link_path="${tabs[-1]}"
        master_path=$(echo "$MASTER_DUPLICATES" | grep -E "^($checksum)" | awk -F'\t' '{print $NF}')
        ln -Tf "$master_path" "$link_path" # forcing (-f) the link to replace the duplicates
        report_line="Replaced $link_path by a link to $master_path"
        log partial "$report_line"
        echo "$report_line" >> $linked_files
    done <<< "$EXTRA_DUPLICATES"
    log status "ok"
    log status -e "\nHard linked files report saved to $linked_files"
}

remove_extras() {
    log status  -e "\nRemoving extra duplicates..."
    removed_files="$TARGET_DIR/CDreport_removed_files.txt"
    echo -n "" > $removed_files
    while IFS=$'\t' read -r -a tabs; do
        path="${tabs[-1]}"
        rm "$path"
        report_line="Removed $path"
        log partial "$report_line"
        echo "$report_line" >> $removed_files
    done <<< "$EXTRA_DUPLICATES"
    log status "ok"
    log status -e "\nRemoved files report saved to $removed_files"
}
#--------------------------------------------------------------------------------------


# OPERATION:
#--------------------------------------------------------------------------------------
if [ "$DO_NOTHING" = 1 ]; then
    search_files
    find_matches
    exit
elif [ "$MOVE_ALL" = 1 ]; then
    search_files
    find_matches
    confirm_action
    move_all
    exit
elif [ "$LINK_EXTRAS" = 1 ]; then
    search_files
    find_matches
    find_extras
    confirm_action
    link_extras
    exit
elif [ "$REMOVE_EXTRAS" = 1 ]; then
    search_files
    find_matches
    find_extras
    confirm_action
    remove_extras
    exit
elif [ "$MOVE_BACK" = 1 ]; then
    search_moved
    confirm_action
    move_back
    exit
fi
#--------------------------------------------------------------------------------------


