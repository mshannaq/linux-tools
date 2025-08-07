tmp-force-cleaner
=================

A secure Bash script that automatically deletes files from the /tmp directory 
that are older than a specified number of HOURS.

This script is intended for use on Linux servers to keep the /tmp directory clean 
without affecting system-critical files.

------------------------------------------------------------
Features
------------------------------------------------------------

- Deletes only files (-type f) — no directories or sockets.
- Skips:
  - *.sock (e.g. mysql.sock)
  - *.pid (process ID files)
  - systemd* files
- Can be scheduled via cron for automated cleanups.
- Logs every cleanup operation with a timestamp.
- Prevents execution unless run by root.
- Customisable cleanup time via one variable.

------------------------------------------------------------
Configuration
------------------------------------------------------------

You can adjust the number of hours after which files are deleted 
by editing the following line at the top of the script:

  CLEANUP_AGE_HOURS=4

Examples:
  CLEANUP_AGE_HOURS=1   → Deletes files older than 1 hour.
  CLEANUP_AGE_HOURS=12  → Deletes files older than 12 hours.

------------------------------------------------------------
Installation
------------------------------------------------------------

1. Create the script file:

   sudo nano /usr/local/bin/tmp-force-cleaner

2. Paste the script (see “The Script” section below).

3. Make it executable:

   sudo chmod +x /usr/local/bin/tmp-force-cleaner

------------------------------------------------------------
Scheduling with Cron
------------------------------------------------------------

To automatically run the script every hour:

1. Edit root’s crontab:

   sudo crontab -e

2. Add the following line:

   0 * * * * /usr/local/bin/tmp-force-cleaner

This will run the script at the top of every hour.

------------------------------------------------------------
Log File
------------------------------------------------------------

By default, the script logs to:

  /var/log/tmp-force-cleaner.log

Each run will include:
- Start timestamp
- End timestamp
- Output of the find command (e.g. errors if any)

You can change the log path by modifying this line:

  LOG_FILE="/var/log/tmp-force-cleaner.log"

------------------------------------------------------------
Security & Safety
------------------------------------------------------------

- The script must be run as root. It will exit immediately if not.
- It only deletes regular files (-type f).
- It excludes critical socket and PID files.
- It is safe to run on production systems when used as described.

------------------------------------------------------------
The Script
------------------------------------------------------------

#!/bin/bash

# tmp-force-cleaner
# Deletes files from /tmp that are older than a specified number of hours.
# Must be run as root.

# ================== CONFIGURATION ==================

# Set cleanup age (in hours)
CLEANUP_AGE_HOURS=4

# Optional: Log file path
LOG_FILE="/var/log/tmp-force-cleaner.log"

# ===================================================

# Exit if not run as root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

# Convert hours to minutes
CLEANUP_AGE_MINUTES=$((CLEANUP_AGE_HOURS * 60))

# Timestamp
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting cleanup (older than $CLEANUP_AGE_HOURS hours)..." >> "$LOG_FILE"

# Run the cleanup
find /tmp -type f -mmin +$CLEANUP_AGE_MINUTES ! -name '*.sock' ! -name '*.pid' ! -name 'systemd*' -delete >> "$LOG_FILE" 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cleanup finished." >> "$LOG_FILE"

------------------------------------------------------------
Notes
------------------------------------------------------------

- This script is compatible with systemd-based or classic init Linux distributions.
- You can test it safely first by replacing -delete with -exec ls -lh {} \;
