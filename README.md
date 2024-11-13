# CHECK DUPLICATES

## Description
**Check_Duplicates** is a Bash script designed to help users manage duplicate files within a specified target directory (and its subdirectories).  It provides options to list, link, move or remove duplicates found based on user-defined criteria, making it faster and easier to organize files and free up disk space.
It is useful for batch processing files, since the usage of metadata-matches, filtering files before performing any actual data-match, speeds this process a lot!

## Installation Instructions
1. **Download the script**: Clone the repository or download the script file directly.
   ```bash
   git clone git@github.com:casarinjr/Check_Duplicates.git
   cd Check_Duplicates
   ```
2. **Set Permissions**: Make the script executable.
   ```bash
   chmod +x check_duplicates.sh
   ```

## Usage
To run the script, use the following command format:
```bash
./check_duplicates.sh [options] target_directory
```

### Options:
	Search operations (one):
       [-r] Recursive search in target directory and all its subdirectories. (default)
       [-d:] Maximum depth of search. Requires any number ≥ 1.

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

	Output verbosity:
       [-q] Quiet: only status and operational messages are echoed in the terminal. (0 precedence)
       [-m] Moderate: final results are echoed additionally. (1 precedence) (default)
       [-v] Verbose: partial results (of each matching process) are echoed additionally. (2 precedence)

Combining options:
 - Search operations cannot be combined, only one option is valid.
 - Match operations can be combined, any combination is valid.
 - File operations cannot be combined, only one option is valid.
 - If combined, the higher output verbosity will take precedent.

### Examples:
1. Checking files with same size and last modified time exclusively in the ~/Downloads directory (no search in subdirectories).
```bash
./check_duplicates.sh -t -d1 ~/Downloads
```
2. Checking files with the same size, same name, same time, same 10 bytes at head and tail, and same checksum.
```bash
./check_duplicates.sh -snthcL ~/Documents
```
3. Creating symbolic links for all matches (size and name) at LINKS_TO_DUPLICATES subdirectory for analysis. Quiet verbosity.
```bash
./check_duplicates.sh -qnS ~/Music
```
4. Moving all matches (size and headtail) to the DUPLICATES directory for analysis. Moderate verbosity.
```bash
./check_duplicates.sh -mhM ~/Videos
```
5. Moving files back to their origin, after they were moved to the ~/Videos/DUPLICATES directory.
```bash
./check_duplicates.sh -B ~/Videos
```
6. Removing all extra copies (same size, time, and checksum) except for one master copy of each. Verbose output.
```bash
./check_duplicates.sh -vtR ~/Pictures/DUPLICATES
```

### Expected behavior and performance:

 1. **Maximum search depth** *-d number* takes a numeric argument. It specifies how deep the find operation will look for files in a directory. It is most useful when you are performing this command in a higher hierarchy directory and do not want to assess all its subdirectories. Hence, *-d 1* will search only the target directory, and *-d 2* will search level 1 and 2 of subdirectories. If *-d#* is not specified, a **Recursive search** *-r* will be performed in all target files and subdirectories.
 2. **Size-match** is always performed, you don't really need to specify *-s* to perform it. It will always be the first thing done. This is the core principle for a speedy performance. No files can be exactly equal if they have different sizes, so there is no point on wasting resources processing a full data check when we can discard a match by a simple metadata check.
 3. **Time-match** *-t* also speeds things a lot. However, it is optional because in some cases, when files were opened and saved without modification or the modification was manually reverted, it would discard matches by presenting different metadata (last modified time) even with the same content (the actual data).
 4. **Name-match** *-n* is pretty fast. Logically, it will not consider files that do not have the exact name match.
 5. **Inode-match** *-i* is useful if you want to manage your hard linked files. There is no need to use any other matching option with it, since files that have the same inode are already pointing to the same data. It is also useful for checking the success of the **Hardink-extras** operation *-H*. Since they do not occupy extra space, files hard linked (same inode) will not appear as duplicates unless this option is on.
 6. **Headtail-match** *-h* checks the first and last 10 bytes of a file. It is the fastest way to assess the actual data (not just the metadata) of a file. It performs fast too because it just checks two slices of the file, **independently of how big the file is**.  Although different files sometimes have the same start and ending (same type and style), when combined with metadata matches (size and date) they will return possible matches without overhead processing. Thus, it is useful for filtering big files before checking their data entirely.
 7. **Checksum-match** *-c* is currently the only full data analysis option available. It performs fast with small files and proportionally decreases in performance as the files increase in size. It is always the last check done, so when checking a lot of big files, it is useful to activate concomitantly other filters available to perform this action only on high probable matches.
 8. **Softlink-all** *-S* operation will create symbolic links at target/LINKS_TO_DUPLICATES directory for all duplicate files found. It is useful for manual assessing duplicate files in an ordered way without changing its original name or location.
 9. **Move-all** *-M* operation will rename files when moving them to the DUPLICATES directory to avoid rewriting over files from different origin subdirectories that would have the same name in the destiny directory. You SHOULD NOT simply delete all files moved to that folder, since then you would have no other copies left. That operation is designed for manual check and deletion, thus you should probably want to keep at least one copy of each duplicate pair or group found. The files are renamed with its previous path so you know where they came from. This way, they will not be renamed/moved if their file path is longer than the maximum length allowed by your file system (typically 255 characters). You should not use this command multiple times in the same target directory, otherwise the renaming operation will build up for as many times as the operation is called.
 10. **Move-back** *-B* operation will only work after a **Move-all** *-M* operation and if you do not rename the /DUPLICATES directory or the files inside it. It will move back the files you decided to keep to its previous location. So you should not rename them if you want the Move-back operation to be able to find that previous location, which is stored in the file names.
 11. **Hardlink-extras** *-H* will only be performed with a **checksum-match,** no matter if the user did not explicitly specify *-c*. This behavior is arbitrary set to prevent unwanted data loss, since checksum-match is currently the most reliable fast way to tell multiple files are true matches. Duplicate files will become hard links pointing to the same file. This feature is helpful for use cases where you do want to keep multiple representation of the same file in different directories but don't want to waste disk space or to periodically sync them.
 12. **Remove-extras** *-R* will also only be performed with a **checksum-match,** even without calling *-c* to prevent unwanted data loss.
 13. Although it is **theoretically possible** for two different files to have the same checksum. Those chances are astronomically low (about 1 in 2<sup>128</sup>). On top of that, when taking into account that the files assessed are at the same device, the same directory and have the same size, a false match becomes **practically impossible**. You can also add date-match and headtail-match to that equation for piece of mind, in which case a false match would be in a realm of conjectures. There is a confirmation prompt showing the results before actually deleting the files; ***PROCEED WITH CAUTION, you are responsible for the data you mess with. It is advised to test the behavior of this operation in a safe environment before going into action!***.
 14. You can use Remove-extras directly in the target directory without any operation before. But **it is good practice to run Remove-extra in the target/DUPLICATES subdirectory after performing a Move-all operation in the target directory**, assessing manually what went there. This way, the delete action will be contained into just what you have already delimited.
 15. **Do  not use this tool with any file operation on directories with system data, it might break your system. This tool was design to manage user data, not system data. It is meant for files that can be renamed, moved or removed.**
