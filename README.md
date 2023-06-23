# Simple Backup (via rsync)

A simple script to backup a user's home directory (or any other location)
to a remote server via SSH/rsync.

Doesn't do any fancy tricks with tarballs, encryption, or differentials.
It's expected that the server administrator is handling all that on the server,
ie: with TrueNAS or some other fileserver running ZFS.

Just a wrapper around the already uber-powerful rsync binary and SFTP subsystem.


## Features

* Fully contained inside one script
* Simple copy of files to remote server
* Restoration/viewing of plain files with any file viewer
* Few dependencies, just needs rsync and ssh
* Verifies host connectivity prior to running (via ping)
* Supports host validation (via SSH host keys)
* Supports _only_ passwordless-logins (via SSH keys)
* Implements lock files for long-running jobs
* Supports transfer throttling for low-power devices/targets
* Supports file exclusions
* Supports multiple backup locations (sources)


## Requirements

1. POSIX-compatible system with `rsync`, `ssh`, and `bash` available.
2. Server with SSH accessible and `rsync` installed.
3. SSH user keys deployed to enable password-less logins.


## Setup / Installation

1. Download [backup.sh](backup.sh) into some location, ie: `~/bin` or `~/.local/bin`
2. `chmod +x backup.sh` or right-click and allow executing as a program
3. Configure parameters contained inside `CONFIGURABLE PARAMETERS` section
4. Run the script, `./backup.sh`

By default, your `$HOME` directory is backed up, but it can be changed by 
modifying/adding lines under 
the `BACKUP SOURCES, PLACE YOUR DIRECTIVES HERE` directive in `backup.sh`.


## Setup Password-less Logins with SSH

Since being able to log into your server via SSH without passwords is required,
that is a prerequisite to running this script.  For a quick primer on achieving that:

```bash
# Run ssh-keygen and [ENTER] through the prompts accepting defaults
ssh-keygen

# Copy the ID to the remote server
ssh-copy-id $USER@YOUR_SERVER_HOSTNAME_OR_IP
```

If using TrueNAS, use the administrative web interface to edit your user account
and copy/paste the key under 

* Accounts -> User -> (user account) -> Edit -> Authentication -> SSH Public Key

Multiple keys can be added, each one on its own newline.  To quickly grab your public key:

```bash
cat ~/.ssh/id_rsa.pub
```


## Setup Cron for Automated Backups

```bash
# Edit the user crontab, selecting the preferred text editor if necessary
crontab -e

# no crontab for charlie - using an empty one
# 
# Select an editor.  To change later, run 'select-editor'.
#   1. /bin/nano        <---- easiest
#   2. /usr/bin/vim.basic
#   3. /usr/bin/vim.tiny
# 
# Choose 1-3 [1]: 2
# crontab: installing new crontab
```

Add the following line to your crontab, with where-ever you placed your `backup.sh` file.
This will run the script once an hour, with the internal `SECONDS_BETWEEN` variable
checking frequency.  This is recommended in case the workstation is powered off
during your expected backup schedule, as it will re-run the backup at the next hour.

```
Run backups
0 * * * * /home/YOURHOME/bin/backup.sh
```


## File Exclusions

This script handles exclusion of files, 
(ie: those already secured with Dropbox/Nextcloud), by allowing for an exclusion list.
To set a list of excluded files, create a plain text file called `simplebackup_excludes.txt`
at the root of your source directory, (ie: for the default `$HOME` source, the filename
would be `/home/USERNAME/simplebackup_excludes.txt`), and enter the list
of directories or files to exclude, (one per line).

Follow the rsync pattern for wildcard or fuzzy matching.

## Configurable Parameters

---

### SECONDS_BETWEEN
Amount of time to pass between backups, (in number of seconds)

* Hourly = 3600
* Daily  = 86400
* Weekly = 604800


---

### R_HOST

Hostname or IP address of target backup server

---

### R_ROOT

Target directory (on remote server) to store backups into
Useful runtime auto-replacements are:

* ${USER} for the current local username
* ${HOSTNAME} for the current local hostname

By using environmental variables, you can use the same script on multiple workstations.

---

### R_USER

Target username to connect with (defaults to current user)
If your remote user is the same as the local user, this can just be the default
otherwise enter the remote username used to login, (ssh keys are expected to be setup)

---

### BW_LIMIT

Transfer rate limit (in kb/s)
* Disable = 0
* 5Mb/s = 51200
* 10Mb/s = 102400
* 100Mb/s = 1024000

---

### TEST

Set to 1 to enable dry-run (useful for development without actually performing a sync)

---

## Road Warriors / Laptops

This script is safe to run on laptops and portable devices which may not always
be on the same network as your backup server.  It will check connectivity to the
server prior to starting.  Additionally, it will verify the host via its SSH host key
to ensure it only connects to your trusted destination.


## Remote Setups

Since this script relies on SSH as the encryption / connection layer, it is safe
to use on a WAN / cloud destination, (or port forwarded through your home gateway).