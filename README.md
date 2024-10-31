# CHECK DUPLICATES

## Description
**Check_Duplicates** is a Bash script designed to help users manage duplicate files within a specified target directory (and its sub-directories).  It provides options to list, move or remove duplicates found based on user-defined criteria, making it faster and easier to organize files and free up disk space.
It is useful for bulking processing files, since the usage of metada matches, filtering files before performing any actual data matches, speeds this process a lot!

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
	Match operations (any):
       [-s] Perform a metadata match by size in bytes. (always)
       [-d] Perform a metadata match by date (last modification time).
       [-h] Perform a data match by bytes in head and tail.
       [-c] Perform a data match by md5 checksum.

	File operations (one):
       [-N] Files are not touched. (default)
       [-M] Move all duplicates found into /DUPLICATES subdirectory.
       [-R] Remove extra duplicates found (keep 1 master copy).

Combining options:
 - Match operations can be combined, any combination is valid. 
 - File operations cannot be combined, only one option is valid.

### Examples: 
1. Checking files with same size and date in the ~/Downloads directory. Results are printed in the terminal.
```bash
./check_duplicates.sh -d ~/Downloads
```
2. Checking files with same size and modified data; then their same head and tail 10 bytes; then their checksum.  Results are redirected to a file for further consultation.
```bash
./check_duplicates.sh -sdhc ~/Documents > duplicates.txt
```
3. Moving all matches (size and headtail) to the DUPLICATES directory for analysis of the user.
```bash
./check_duplicates.sh -hM ~/Videos
```
4. Removing all extra copies (same size, data and checksum) except for one master copy that is kept.
```bash
./check_duplicates.sh -dR ~/Pictures
```

### Expected behavior and performance:

 1. **Size-match** is always performed, you don't really need to specify *-s* to perform it. It will always be the first thing done. This is the core principle for a speedy performance. No files can be equal if they have different sizes, so there is no point on wasting resources processing a full data check when we can discard a match by a simple metadata check.
 2. **Date-match** *-d* also speeds things a lot. However, it is optional because in few cases it can discard matches equal content but different metadata. When a user modifies the content of a copy, save it, then manually modify back the content as previous, saving it again. It will have a different last modified time in their metadata, even though in practice the content of the original and the copy are the same.
 3. **Headtail-match**  checks the first and last 10 bytes of a file. It is the fastest way to assess the actual data (not just the metadata) of a file. It performs fast too because it just checks two slices of the file, **independently of how big the file is**.  Although theoretically, many files can have the same start and ending, when combined with metadata matches (size and date) they will likely return true matches without overhead processing. Thus, it can't be useful to filter big files before a full data check.
 4. **Checksum-match** is currently the only full data analysis option available. It performs fast with small files and proportionally decreases in performance as the files increase in size. It is always the last check done, so when checking a lot of big files, it is useful to activate concomitantly other filters available to perform this action only on high probable matches. 
 5. **Move-all** operation will rename files when moving them to the DUPLICATES directory to avoid rewriting over files from different origin subdirectories that would have the same name in the destiny directory. You SHOULD NOT simply delete all files moved to that folder, since then you would have no other copies left. That operation is designed for manual check and deletion, thus you should probably want to keep at least one copy of each duplicate pair or group found.
 6. **Remove-extras** will only be performed with a **checksum-match,** no matter if the user did not explicitly specify *-c*. This behavior is arbitrary set to prevent unwanted data loss, since checksum-match is currently the most reliable fast way to tell multiple files are true matches.
 7. Although it is **theoretically possible** for two different files to have the same checksum hash. Those chances are astronomically low (about 1 in 2<sup>128</sup>). On top of that, when taking into account that the files assessed are at the same device, the same directory and have the same size, a false match becomes **practically impossible**. You can also add date-match and headtail-match to that equation for piece of mind, in which case a false match would be in a realm of conjectures. There is a confirmation prompt showing the results before actually deleting the files; ***PROCEED WITH CAUTION, you are responsible for the data you mess with. It is advised to test the behavior of this operation in a safe environment before going into action!***
