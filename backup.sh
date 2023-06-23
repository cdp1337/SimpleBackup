#!/bin/bash
#
# Simple backup script (via rsync and SSH)
#
# v1.0.0
# @author Charlie Powell <cdp1337@veraciousnetwork.com>
# @license MIT

##############################################
### CONFIGURABLE PARAMETERS
##############################################

# Amount of time to pass between backups, (in number of seconds)
# Hourly = 3600
# Daily  = 86400
# Weekly = 604800
#
SECONDS_BETWEEN=3600

# Hostname or IP address of target backup server
#
R_HOST="nas.network.local"

# Target directory (on remote server) to store backups into
# Useful runtime auto-replacements are:
# * ${USER} for the current local username
# * ${HOSTNAME} for the current local hostname
#
# By using environmental variables, you can use the same script on multiple workstations.
#
R_ROOT="/mnt/store/home/${USER}/Backups/${HOSTNAME}"

# Target username to connect with (defaults to current user)
# If your remote user is the same as the local user, this can just be the default
# otherwise enter the remote username used to login, (ssh keys are expected to be setup)
#
R_USER="${USER}"

# Transfer rate limit (in kb/s)
# Disable = 0
# 5Mb/s = 51200
# 10Mb/s = 102400
# 100Mb/s = 1024000
#
BW_LIMIT=0

# Set to 1 to enable dry-run (useful for development without actually performing a sync)
#
TEST=0


















##############################################
### INTERNAL LOGIC, SKIP PAST THIS
##############################################

# Return code for a backup attempt that ran before the configured time has lapsed, (common with crons)
ERROR_TOO_SOON=1

# Return code for target server not reachable
ERROR_NOT_REACHABLE=2

# Return code for bad SSH host or user keys, expected if SSH auth isn't setup or MITM attacks
ERROR_BAD_KEYS=3

# Return code for failure during the file transfer from rsync
ERROR_XFER=4

# Return code for another backup process running
ERROR_ANOTHER_PROCESS=5

# Return code for when the user presses CTRL+C to send SIGINT
ERROR_SIGINT=255


##
# Perform the actual backup of a requested directory
#
# @param $1 (string) Source directory (with trailing slash)
# @param $2 (string,optional) Target directory within the root backup directory
#
function backup() {
  SRC="$1"
  DEST="$2"
  # Default options:
  # -a = Archive, enables -r, -l, -p, -t, -g, -o, -D
  # -r = Recurse into directories
  # -l = Copy symlinks as symlinks
  # -p = Preserve permissions
  # -t = Preserve modification times
  # -g = Preserve group
  # -o = Preserve owner
  # -D = enables --specials
  # --specials = Preserve special files
  # -C = CVS exclude auto-ignore
  # -X = Preserve extended attributes
  OPTS="-ahCX --bwlimit=$BW_LIMIT --delete"

  if [ -z "$DEST" ]; then
    DEST="$R_ROOT"
  else
    DEST="$R_ROOT/$DEST"
  fi

  echo "Starting backup of $SRC -> $R_HOST:$DEST"

  if [ $TEST -eq 1 ]; then
    OPTS="$OPTS --dry-run"
    echo "(PERFORMING DRY-RUN TEST)"
  fi

  # Read list from exclude filelist if present
  if [ -e "$SRC/simplebackup_excludes.txt" ]; then
    OPTS="$OPTS --exclude-from="$SRC/simplebackup_excludes.txt""
    echo "Excluding files listed within $SRC/simplebackup_excludes.txt"
  else
    echo "File simplebackup_excludes.txt not found within $SRC, no files excluded"
  fi

  if [ $TEST -ne 1 ]; then
    # Auto-create the target remote directory
    ssh ${R_USER}@nas.house.local -o BatchMode=yes "mkdir -p "$DEST""
  fi

  # Perform the actual backup
  if ! rsync $OPTS "$SRC" ${R_USER}@$R_HOST:"$DEST"; then
  	echo "Error occurred while trying to transfer to $R_HOST:$DEST"
  	cleanup_exit $ERROR_XFER
  fi
}

##
# Format a time delta in number of seconds to a human-friendly string
#
# @param $1 (int) number of seconds
# @return (string) one of:
#         * N hours             (when +3600 and 0 minutes)
#         * N hours N minutes   (when +3600 and >0 minutes)
#         * N minutes           (when +60 and 0 seconds)
#         * N minutes N seconds (when +60 and >0 seconds)
#         * N seconds           (default, when <=60)
#
function format_seconds() {
  SEC=$1
  H=0
  M=0

  if [ $SEC -ge 3600 ]; then
    let "H=$SEC/3600"
    let "SEC=$SEC%3600"
  fi

  if [ $SEC -ge 60 ]; then
    let "M=$SEC/60"
    let "SEC=$SEC%60"
  fi


  if [ $H -gt 0 -a $M -gt 0 ]; then
    echo "$H hours $M minutes"
  elif [ $H -gt 0 ]; then
    echo "$H hours"
  elif [ $M -gt 0 -a $SEC -gt 0 ]; then
    echo "$M minutes $SEC seconds"
  elif [ $M -gt 0 ]; then
    echo "$M minutes"
  elif [ $SEC -gt 0 ]; then
    echo "$SEC seconds"
  else
    echo "0 seconds"
  fi
}

##
# Catch CTRL+C / SIGINT to cleanup the lock file
#
function trap_exit() {
  cleanup_exit $ERROR_SIGINT
}

##
# Exit the script and cleanup the lock file
#
# @param $1 (int) Return code to exit
#
function cleanup_exit() {
  END_TIME=$(date +%s)
  let "RUN_TIME=$END_TIME-$START_TIME"
  echo "Aborting backup after $(format_seconds $RUN_TIME)"
  rm ~/.config/simplebackup.lock
  exit $1
}


# Catch CTRL+C and run trap_exit to perform cleanup prior to exiting
trap 'trap_exit' SIGINT


# Retrieve the last time this backup ran
if [ -e ~/.config/simplebackup.last ]; then
	LAST_RUN="$(cat ~/.config/simplebackup.last)"
else
	LAST_RUN="0"
fi
let "TIME_DELTA=$(date +%s)-$LAST_RUN"

# Check the last time this backup ran
if [ $TIME_DELTA -lt $SECONDS_BETWEEN ]; then
	echo "Last backup ran $(format_seconds $TIME_DELTA) ago, less than $(format_seconds $SECONDS_BETWEEN) so not running"
	exit $ERROR_TOO_SOON
else
  if [ "$LAST_RUN" == "0" ]; then
    echo "No backups ever completed, continuing backup"
  else
    echo "Last backup ran $(format_seconds $TIME_DELTA) ago, continuing backup"
  fi
fi

# Only run if the target host is reachable
if ! ping -c1 -w1 "$R_HOST"; then
	echo "Unable to connect to $R_HOST, not running"
	exit $ERROR_NOT_REACHABLE
else
  echo "$R_HOST is reachable, continuing backup"
fi


# Verify if we can connect with the current user
# To ensure host validity, DO NOT use StrictHostKeyChecking=no here!
if ! ssh ${R_USER}@nas.house.local -o BatchMode=yes 'echo "Connected as $(whoami) to $(uname -a)"'; then
  echo "Unable to verify $R_HOST via SSH, either the target changed or your SSH keys are not setup yet"
  exit $ERROR_BAD_KEYS
fi


# Only allow one process at a time
if [ -e ~/.config/simplebackup.lock ]; then
  LAST_PID="$(cat ~/.config/simplebackup.lock)"
  if ! ps h -p $LAST_PID; then
    echo "Another backup process is running!"
    exit $ERROR_ANOTHER_PROCESS
  fi
fi
echo -n "$$" > ~/.config/simplebackup.lock


# Track the time the backup _started_ so the tracker can be relatively consistent
START_TIME=$(date +%s)

















##############################################
### BACKUP SOURCES, PLACE YOUR DIRECTIVES HERE
##############################################

# Start list of backups to perform, each filesystem/directory one-per-line
# Format:
# backup "SOURCE" "DESTINATION"
# Where source (first parameter) is the local directory, INCLUDE a trailing slash!
# and destination (second parameter) is the remote directory WITHIN the root backup location
#
# eg: if the target is /backups/${USER}/ and the destination is "mybackup",
#     the resulting directory will be /backups/${USER}/mybackups on the remote server.
#
# If you need to backup multiple locations, just call `backup` multiple times with the requested locations.
backup "$HOME/" "home"















##############################################
### CLOSING LOGIC
##############################################

END_TIME=$(date +%s)
let "RUN_TIME=$END_TIME-$START_TIME"

if [ $TEST -ne 1 ]; then
  echo -n $START_TIME > ~/.config/simplebackup.last
fi
echo "Backup completed in $(format_seconds $RUN_TIME)"
rm ~/.config/simplebackup.lock
exit 0
