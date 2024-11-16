#!/bin/bash

# Author: Amauri Casarin Junior
# Purpose: Batch search and processing duplicate files.
# License: GPL-3.0 license
# Version: 1.1
# Date: November 16, 2024

usage_message="Usage: $0 [-options] target_directory

Options:
        Search operations (one):
        [-r] Recursive search in target directory and all its subdirectories. (default)
        [-d:] Maximum depth of search. Requires any integer ≥ 1.

        Match operations (any):
        [-i] Perform a metadata match by inode (find hard links).
        [-n] Perform a metadata match by file name.
        [-s] Perform a metadata match by size in bytes. (default)
        [-t] Perform a metadata match by last modified time.
        [-h] Perform a data match by 10 bytes in head and tail.
        [-c] Perform a data match by md5 checksum.

        File operations (one):
        [-L] List all duplicate files found. (default)
        [-S] Create soft links in target/LINKS_TO_DUPLICATES directory for the duplicate files found.
        [-M] Move all duplicates found into target/DUPLICATES subdirectory.
        [-B] Move back files in target/DUPLICATES directory to its origin.
        [-H] Hard link extra duplicates (replace duplicate files by hard links, saving disk space).
        [-R] Remove extra duplicates found, keeping just 1 master copy of each match.
        [-C:] Copy unique (non duplicate) files from a reference directory.

        Output verbosity:
        [-q] Quiet: echo only status and operational messages. (0 precedence)
        [-m] Moderate: echo final results additionally. (1 precedence) (default)
        [-v] Verbose: echo partial results additionally and creates a log file. (2 precedence)


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
NAME_MATCH=false
EXTENSION_MATCH=false
SIZE_MATCH=true
INODE_MATCH=false
TIME_MATCH=false
HEADTAIL_MATCH=false
CHECKSUM_MATCH=false
# FILE FLAGS
LIST_ALL=1
SOFTLINK_ALL=0
MOVE_ALL=0
MOVE_BACK=0
HARDLINK_EXTRAS=0
REMOVE_EXTRAS=0
COPY_UNIQUES=0
# OUTPUT VARIABLES
verbosity=1 # 0 quiet, 1 normal and 2 verbose.
#--------------------------------------------------------------------------------------

#INPUT CHECKS
#--------------------------------------------------------------------------------------
# Process options using getopts
while getopts ":rd:qmvnestihcLSMBHRC:" opt; do
    case "$opt" in
        r) RECURSIVE_SEARCH=1;;

        d) DEPTH_SEARCH=1; RECURSIVE_SEARCH=0;
            if [[ "$OPTARG" =~ ^[0-9]+$ ]] && [ "$OPTARG" -ge 1 ]; then
                max_depth=${OPTARG}
                echo "Search files up to $max_depth level deep."
            else
                echo "Error: $OPTARG is not a valid integer argument for option -d (>= 1)"
                exit 1
            fi;;

        q) verbosity=0;;

        m) verbosity=1;;

        v) verbosity=2 ;;


        n) NAME_MATCH=true;;

        e) EXTENSION_MATCH=true;;

        s) SIZE_MATCH=true;;

        t) TIME_MATCH=true;;

        i) INODE_MATCH=true;;

        h) HEADTAIL_MATCH=true; headtail_length=10;;

        c) CHECKSUM_MATCH=true;;


        L) LIST_ALL=1; operation_name="list";;

        S) SOFTLINK_ALL=1; operation_name="soft link"; LIST_ALL=0;;

        M) MOVE_ALL=1; operation_name="move"; LIST_ALL=0;;

        B) MOVE_BACK=1; operation_name="move back"; LIST_ALL=0;;

        H) HARDLINK_EXTRAS=1; operation_name="hard link"; LIST_ALL=0; CHECKSUM_MATCH=true;; # for safety, only allows deletion with checksum match.

        R) REMOVE_EXTRAS=1; operation_name="remove"; LIST_ALL=0; CHECKSUM_MATCH=true;; # for safety, only allows deletion with checksum match.

        C) COPY_UNIQUES=1; operation_name="copy"; LIST_ALL=0; CHECKSUM_MATCH=true;
            if [[ -d "$OPTARG" ]]; then
                REFERENCE_DIR="$OPTARG"
                echo "Reference directory provided: $REFERENCE_DIR"
            else
                echo "Error: $OPTARG is not a valid directory"
                exit 1
            fi;;


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
elif [ "$(( LIST_ALL + SOFTLINK_ALL+ MOVE_ALL + MOVE_BACK + HARDLINK_EXTRAS + REMOVE_EXTRAS + COPY_UNIQUES))" -gt 1 ]; then
    echo "Error: File operations L, S, M, B, H, R or C cannot be used together."
    echo "$usage_message"
    exit 1
elif [ -d "$1" ]; then
    TARGET_DIR="$1"
    # Set inner directory for duplicate files or links
    DUPLICATES_DIR="$TARGET_DIR/DUPLICATES"
    LINKS_DIR="$TARGET_DIR/LINKS_TO_DUPLICATES"
    echo "Target directory provided: $TARGET_DIR"
else
    echo "Error: Invalid target directory: $1"
    echo "$usage_message"
    exit 1
fi
#--------------------------------------------------------------------------------------


# LOGS
#--------------------------------------------------------------------------------------
# Log file for verbosity = 3
if [ "$verbosity" = 2 ]; then
    # Get the current timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")

    # Redirecting output to the log file
    exec > >(tee -a "$TARGET_DIR/CD_log_${timestamp}.log") 2>&1
fi

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
#--------------------------------------------------------------------------------------

# SEARCH FUNCTIONS
#--------------------------------------------------------------------------------------
# Structure of the data for analisys
header=''
fields=("Size" "Headtail" "Checksum" "Time" "Inode" "Name" "Extension" "Path")

# Create index arrays for columns and tabs names
declare -A columns_index
declare -A tabs_index
for index in "${!fields[@]}"; do
    field="${fields[$index]}"
    tabs_index[$field]=$index
    columns_index[$field]=$((index + 1))  # Adding 1 to convert from 0-based to 1-based index
    if [ -z "$header" ]; then
        header="$field"
    else
        header="$header\t$field"
    fi
done

header="$(echo -e "$header")"

split_extensions() {
  ASSESSED_FILES=$1
  # Processing the names of files and splitting their extensions using awk
  data_update=$(awk -F'\t' -v OFS='\t' -v name="${columns_index["Name"]}" -v ext="${columns_index["Extension"]}" '{
    match($name, /^(.*)\.([^.]*)$/, arr)
    basename = (arr[1] != "") ? arr[1] : $name
    extension = (arr[2] != "") ? toupper(arr[2]) : "-"  # Convert extension to uppercase

    $name = basename
    $ext = extension
    print
  }' <<< "$ASSESSED_FILES")
  ASSESSED_FILES=$data_update
}


search_files() {
    local directory=$1

    log status -n "Searching files in $directory... "
    # Find metadata for all files inside the directory
    print_format="%s\t-\t-\t%T+\t%i\t%f\t-\t%p\n" # "-" for reserved non "find" fields
    if [ "$DEPTH_SEARCH" = 1 ]; then
        ASSESSED_FILES="$(find "$directory" -maxdepth "$max_depth" -type f -size +0c -printf "$print_format")"
    else
        ASSESSED_FILES="$(find "$directory" -type f -size +0c -printf "$print_format")"
    fi
    split_extensions "$ASSESSED_FILES"
    total_assessed="$(echo "$ASSESSED_FILES" | grep -c -v '^$')"
    log status "ok"
    log status -e "Files found: $total_assessed\n"


}

search2d_files() {
    TARGET_DIR=$1
    REFERENCE_DIR=$2

    search_files "$TARGET_DIR"
    TARGET_FILES=$ASSESSED_FILES
    search_files "$REFERENCE_DIR"
    REFERENCE_FILES=$ASSESSED_FILES

    if [ "$total_assessed" = 0 ];then
        log status "No files found in reference directory $directory."
        exit
    else
        # Merge REFERENCE_FILES and TARGET_FILES to process duplicates
        MERGED_FILES="$(echo -e "$TARGET_FILES\n$REFERENCE_FILES" | sort -n)"
    fi
}


search_moved() {
    # Find metadata for all files inside the DUPLICATE directory
    local directory=$1
    MOVED_FILES="$(find "$directory" -type f -printf "%p\n" | sort -n)"
    total_found="$(echo "$MOVED_FILES" | grep -c -v '^$')"

    if [ "$total_found" = 0 ];then
        log status "No files found in $directory."
        exit
    fi
}

get_duplicates() {
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
        log partial -E "$DUPLICATES" | sort -n
        log status -E "Found $match_name-duplicates: $total_duplicates"
        log partial ""
    fi
}

get_uniques() {
    match_name="$2"
    log status -E "Filtering unique $match_name elements..."
    UNIQUES=$(awk -F'\t' -v cols="${match_columns[*]}" '
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
    }' <<< "$1")
}


find_matches() {
    # METADATA MATCH
    ASSESSED_FILES=$1
    match_columns=()

    match_name="Inode"
    match_columns=(${columns_index[$match_name]})
    if [ "$INODE_MATCH" = true ];then
        get_duplicates "$ASSESSED_FILES" "$match_name"
        return # no need for any other check if inode_match
    else # Discard hard links (keep just one file per inode)
        get_uniques "$ASSESSED_FILES" "$match_name"
        ASSESSED_FILES=$UNIQUES # update

    fi
    match_columns=() # restart with empity match_columns after assessing inodes

    if [ "$SIZE_MATCH" = true ];then
        match_name="Size"
        match_columns+=(${columns_index[$match_name]})
        get_duplicates "$ASSESSED_FILES" "$match_name"
        ASSESSED_FILES=$DUPLICATES #update
    fi

    if [ "$NAME_MATCH" = true ];then
        match_name="Name"
        match_columns+=(${columns_index[$match_name]})
        get_duplicates "$ASSESSED_FILES" "$match_name"
        ASSESSED_FILES=$DUPLICATES #update
    fi

    if [ "$EXTENSION_MATCH" = true ];then
        match_name="Extension"
        match_columns+=(${columns_index[$match_name]})
        get_duplicates "$ASSESSED_FILES" "$match_name"
        ASSESSED_FILES=$DUPLICATES #update
    fi

    if [ "$TIME_MATCH" = true ];then
        match_name="Time"
        match_columns+=(${columns_index[$match_name]})
        get_duplicates "$ASSESSED_FILES" "$match_name"
        ASSESSED_FILES=$DUPLICATES #update
    fi


    # HEADTAIL-DATA MATCH
    if [ "$HEADTAIL_MATCH" = true ];then
        match_name="Headtail"
        match_columns+=(${columns_index[$match_name]})

        local data_update=''
        counter=0
        while IFS=$'\t' read -r -a tabs; do
            counter=$((counter + 1))
            printf "\rGetting headtail-data... %d/%d " "$counter" "$total_duplicates"
            path="${tabs[${tabs_index["Path"]}]}"
            HEAD="$(head -c $headtail_length "$path" | xxd -p)"
            TAIL="$(tail -c $headtail_length "$path" | xxd -p)"
            headtail="${HEAD}${TAIL}"
            tabs[${tabs_index[$match_name]}]="$headtail"   # Update the headtail value in the tabs array
            data_update+="$(IFS=$'\t'; printf "${tabs[*]}")\n" # Reconstruct the line with update

        done <<< "$ASSESSED_FILES"
        echo -e "ok"
        ASSESSED_FILES="$(echo -e "$data_update")"
        get_duplicates "$ASSESSED_FILES" "$match_name"
        ASSESSED_FILES=$DUPLICATES #update
    fi

        # CHECKSUM-DATA MATCH
    if [ "$CHECKSUM_MATCH" = true ]; then
        match_name="Checksum"
        match_columns+=(${columns_index[$match_name]})

        data_update=''
        counter=0
        while IFS=$'\t' read -r -a tabs; do
            counter=$((counter + 1))
            printf "\rGetting checksum data... %d/%d " "$counter" "$total_duplicates"
            path="${tabs[${tabs_index["Path"]}]}"
            checksum=$(md5sum "$path" | cut -f 1 -d " ") # Calculate the new checksum
            tabs[${tabs_index[$match_name]}]="$checksum"   # Update the checksum value in the tabs array
            data_update+="$(IFS=$'\t'; printf "${tabs[*]}")\n" # Reconstruct the line with update
        done <<< "$ASSESSED_FILES"
        echo -e "ok"
        ASSESSED_FILES="$(echo -e "$data_update")"
        get_duplicates "$ASSESSED_FILES" "$match_name"
        ASSESSED_FILES=$DUPLICATES # Update
    fi

    DUPLICATES=$ASSESSED_FILES
}

find_extras() {
    DUPLICATES=$1
    get_uniques "$DUPLICATES"
    MASTER_DUPLICATES="$UNIQUES"
    EXTRA_DUPLICATES="$(echo "$DUPLICATES" | grep -F -v -x "$MASTER_DUPLICATES")"
}

find2d_uniques() {
    MERGED_FILES=$1
    find_matches "$MERGED_FILES"
    MERGED_DUPLICATES=$DUPLICATES
    REFERENCE_FILES_path=$(awk -F'\t' '{print $NF}' <<< "$REFERENCE_FILES")

    # Split the duplicates
    REFERENCE_DUPLICATES=$(grep -F "$REFERENCE_FILES_path"  <<< "$MERGED_DUPLICATES")
    TARGET_DUPLICATES=$(grep -F -v -x "$REFERENCE_DUPLICATES" <<< "$MERGED_DUPLICATES")
    # remerger but with the target on top so it takes precedence in the get_uniques function
    remerged_duplicates="$(echo -e "$TARGET_DUPLICATES\n$REFERENCE_DUPLICATES")"

    get_uniques "$remerged_duplicates"
    MASTER_DUPLICATES=$UNIQUES
    REFERENCE_EXTRAS=$(grep -F -v -x "$MASTER_DUPLICATES" <<< "$REFERENCE_DUPLICATES") # files not to be copied
    REFERENCE_EXTRAS_path=$(awk -F'\t' '{print $NF}' <<< "$REFERENCE_EXTRAS")
    REFERENCE_UNIQUES_path=$(grep -F -v -x "$REFERENCE_EXTRAS_path" <<< "$REFERENCE_FILES_path") # files to be copied
}

#--------------------------------------------------------------------------------------


# FILE OPERATION FUNCTIONS
#--------------------------------------------------------------------------------------
confirm_action() {
    operation_name=$1
    echo ""
    read -p "Are you sure you want to $operation_name those files? [yes/no]: " response
    case "$response" in
        yes) return 0;;
        no) echo "Operation canceled. No files were touched."; exit;;
        *) echo "Invalid response. Please enter 'yes' or 'no'."; confirm_action;;
    esac
}


list_all() {
    DUPLICATES="$(echo "$1" | sort -n)"
    log status -e "\nResults:"
    log final -E "$DUPLICATES"
    log status -e "$total_assessed files assessed. $total_duplicates duplicates found."

    duplicates_report="$TARGET_DIR/CDreport_duplicates.txt"
    echo "$header" > "$duplicates_report"
    echo "$DUPLICATES" >> "$duplicates_report"
    log status -e "\nDuplicate files report saved to $duplicates_report"
}

softlink_all() {
    DUPLICATES=$1
    counter=0
    mkdir -p "$LINKS_DIR"  # Create directory if it doesn't exist
    log status -en "\nCreating soft links of duplicates..."
    softlinked_files="$TARGET_DIR/CDreport_softlinked_files.txt"
    echo -n "" > "$softlinked_files"
    while IFS=$'\t' read -r -a tabs; do
        counter=$((counter + 1))
        formatted_counter=$(printf "%0${#total_duplicates}d" "$counter") # counter with leading zeros
        duplicate_path="${tabs[${tabs_index["Path"]}]}"
        basename="${tabs[${tabs_index["Name"]}]}"
        link_path="${LINKS_DIR}/$formatted_counter - $basename"
        ln -s "$duplicate_path" "$link_path"
        report_line="Created a soft link at $link_path pointing to $duplicate_path"
        log partial "$report_line"
        echo "$report_line" >> "$softlinked_files"
    done <<< "$DUPLICATES"
    log status "ok"
    log status -e "\nSoft linked files report saved to $softlinked_files"
}


move_all() {
    DUPLICATES=$1
    counter=0
    mkdir -p "$DUPLICATES_DIR"  # Create directory if it doesn't exist
    log status -en "\nMoving duplicates..."
    moved_files="$TARGET_DIR/CDreport_moved_files.txt"
    echo -n "" > "$moved_files"
    while IFS=$'\t' read -r -a tabs; do
        counter=$((counter + 1))
        formatted_counter=$(printf "%0${#total_duplicates}d" "$counter") # counter with leading zeros
        path="${tabs[${tabs_index["Path"]}]}"
        relative_path=$(realpath --relative-to="$TARGET_DIR" "$path")
        new_filename="${formatted_counter} {:${relative_path//\//|}"  # Replace / with |
        mv "$path" "${DUPLICATES_DIR}/$new_filename"
        report_line="Moved $path to $DUPLICATES_DIR"
        log partial "$report_line"
        echo "$report_line" >> "$moved_files"
    done <<< "$DUPLICATES"
    log status "ok"
    log status -e "\nMoved files report saved to $moved_files"
}

list_copies() {
    REFERENCE_UNIQUES_path="$(echo "$1" | sort -n)"
    REFERENCE_EXTRAS_path="$(echo "$2" | sort -n)"
    total_copy="$(echo "$REFERENCE_UNIQUES_path" | grep -c -v '^$')"
    total_leave="$(echo "$REFERENCE_EXTRAS_path" | grep -c -v '^$')"

    log status -e "\nDuplicate files from reference not to be copied:"
    log final -E "$REFERENCE_EXTRAS_path"
    log status -e "Total: $total_leave"

    log status -e "\nUnique files from reference to be copied:"
    log final -E "$REFERENCE_UNIQUES_path"
    log status -e "Total: $total_copy"

    duplicates_report="$TARGET_DIR/CDreport_duplicates.txt"
    echo "$header" > "$duplicates_report"
    echo "$DUPLICATES" >> "$duplicates_report"
    log status -e "\nDuplicate files report saved to $duplicates_report"


    if [ "$total_copy" = 0 ];then
        log status -e "No unique files found to be copied."
        exit
    else
        copy_report="$TARGET_DIR/CDreport_copy.txt"
        echo "$REFERENCE_UNIQUES_path" > "$copy_report"
        log status -e "Unique files report saved to $copy_report"
    fi

}

copy_uniques() {
    REFERENCE_UNIQUES_path=$1
    log status -en "\nCoping files... "
    copied_report="$TARGET_DIR/CDreport_copied_files.txt"
    noncopied_report="$TARGET_DIR/CDreport_noncopied_files.txt"
    echo -n "" > "$copied_report"
    echo -n "$REFERENCE_EXTRAS_path" > "$noncopied_report"
    while read -r path; do
        relative_path=$(realpath --relative-to="$REFERENCE_DIR" "$path")
        new_path="${TARGET_DIR}/$relative_path"
        dir_path="$(dirname "$new_path")"
        mkdir -p "$dir_path"
        cp --update=none "$path" "$new_path" || cp "$path" "$dir_path/$(basename "${path%.*}")_$(date +%s).${path##*.}"

        report_line="Copied $path to $new_path"
        log partial "$report_line"
        echo "$report_line" >> "$copied_report"
    done <<< "$REFERENCE_UNIQUES_path"
    log status -E "ok"
    log status -e "\nCopied files report saved to $copied_report"
    log status -e "\nNoncopied files report saved to $noncopied_report"
}



list_moved() {
    MOVED_FILES="$(echo "$1" | sort -n)"
    log status -e "Files found to be moved back:"
    log final -E "$MOVED_FILES"
    log status -e "Total: $total_found\n"

    moved_found="$TARGET_DIR/CDreport_moved_found.txt"
    echo "$MOVED_FILES" > "$moved_found"
    log status -e "\nMoved-found report saved to $moved_found"
}

move_back () {
    MOVED_FILES=$1
    log status -en "\nMoving files back..."
    movedback_files="$TARGET_DIR/CDreport_movedback_files.txt"
    echo -n "" > "$movedback_files"
    while read -r currernt_path; do
        formatted_old_path="${currernt_path#*\{:}"  # Remove everything up to the first '{:'
        old_path="${TARGET_DIR}/${formatted_old_path//\|//}"  # Replace back all '|' with '/'
        mv "$currernt_path" "$old_path"
        report_line="Moved back to $old_path"
        log partial "$report_line"
        echo "$report_line" >> "$movedback_files"
    done <<< "$MOVED_FILES"
    log status -E "ok"
    log status -e "\nMoved back files report saved to $movedback_files"
}

list_extras() {
    MASTER_DUPLICATES="$(echo "$1" | sort -n)"
    EXTRA_DUPLICATES="$(echo "$2" | sort -n)"
    total_keep="$(echo "$MASTER_DUPLICATES" | grep -c -v '^$')"
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
    echo "$header" > "$master_duplicates_file"
    echo "$header" > "$extra_duplicates_file"
    echo "$MASTER_DUPLICATES" >> "$master_duplicates_file"
    echo "$EXTRA_DUPLICATES" >> "$extra_duplicates_file"
    log status -e "\nMaster duplicates report saved to $master_duplicates_file"
    log status -e "Extra duplicates report saved to $extra_duplicates_file"
}

hardlink_extras() {
    EXTRA_DUPLICATES=$1
    log status  -en "\nReplacing extra duplicates by hard links..."
    hardlinked_files="$TARGET_DIR/CDreport_hardlinked_files.txt"
    echo -n "" > "$hardlinked_files"
    while IFS=$'\t' read -r -a tabs; do
        checksum="${tabs[${tabs_index["Checksum"]}]}"
        link_path="${tabs[${tabs_index["Path"]}]}"
        master_path="$(echo "$MASTER_DUPLICATES" | grep -F $'\t'"$checksum"$'\t' | awk -F'\t' '{print $NF}')"
        ln -Tf "$master_path" "$link_path" # forcing (-f) the link to replace the duplicates
        report_line="Replaced $link_path by a link to $master_path"
        log partial "$report_line"
        echo "$report_line" >> "$hardlinked_files"
    done <<< "$EXTRA_DUPLICATES"
    log status "ok"
    log status -e "\nHard linked files report saved to $hardlinked_files"
}

remove_extras() {
    EXTRA_DUPLICATES=$1
    log status  -en "\nRemoving extra duplicates... "
    removed_files="$TARGET_DIR/CDreport_removed_files.txt"
    echo -n "" > "$removed_files"
    while IFS=$'\t' read -r -a tabs; do
        path="${tabs[${tabs_index["Path"]}]}"
        rm "$path"
        report_line="Removed $path"
        log partial "$report_line"
        echo "$report_line" >> "$removed_files"
    done <<< "$EXTRA_DUPLICATES"
    log status "ok"
    log status -e "\nRemoved files report saved to $removed_files"
}
#--------------------------------------------------------------------------------------


# OPERATION:
#--------------------------------------------------------------------------------------
if [ "$LIST_ALL" = 1 ]; then
    search_files "$TARGET_DIR"
    find_matches "$ASSESSED_FILES"
    list_all "$DUPLICATES"
    exit
elif [ "$SOFTLINK_ALL" = 1 ]; then
    search_files "$TARGET_DIR"
    find_matches "$ASSESSED_FILES"
    list_all "$DUPLICATES"
    softlink_all "$DUPLICATES"
    exit
elif [ "$MOVE_ALL" = 1 ]; then
    search_files "$TARGET_DIR"
    find_matches "$ASSESSED_FILES"
    list_all "$DUPLICATES"
    confirm_action "$operation_name"
    move_all "$DUPLICATES"
    exit
elif [ "$HARDLINK_EXTRAS" = 1 ]; then
    search_files "$TARGET_DIR"
    find_matches "$ASSESSED_FILES"
    find_extras "$DUPLICATES"
    list_extras "$MASTER_DUPLICATES" "$EXTRA_DUPLICATES"
    confirm_action "$operation_name"
    hardlink_extras "$EXTRA_DUPLICATES"
    exit
elif [ "$REMOVE_EXTRAS" = 1 ]; then
    search_files "$TARGET_DIR"
    find_matches "$ASSESSED_FILES"
    find_extras "$DUPLICATES"
    list_extras "$MASTER_DUPLICATES" "$EXTRA_DUPLICATES"
    confirm_action "$operation_name"
    remove_extras "$EXTRA_DUPLICATES"
    exit
elif [ "$MOVE_BACK" = 1 ]; then
    search_moved "$DUPLICATES_DIR"
    list_moved "$MOVED_FILES"
    confirm_action "$operation_name"
    move_back "$MOVED_FILES"
    exit
elif [ "$COPY_UNIQUES" = 1 ]; then
    search2d_files "$TARGET_DIR" "$REFERENCE_DIR"
    find2d_uniques "$MERGED_FILES"
    list_copies "$REFERENCE_UNIQUES_path" "$REFERENCE_EXTRAS_path"
    confirm_action "$operation_name"
    copy_uniques "$REFERENCE_UNIQUES_path"
    exit
fi
#--------------------------------------------------------------------------------------


