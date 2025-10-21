#!/bin/bash

# ===========================================================================
# Author: Arnold Aristotle Tayag
# Date created: 01-May-2015
# Description:
#   Oracle Full Database Backup Script
#   Performs a full backup of the Oracle database and sends email results
# Schedule: Daily at 1:00 AM via cron
#   0 1 * * * /usr/local/bin/oracle_full_backup.sh >> /dev/null 2>&1
# Change Log:
#
# ===========================================================================


# ==========================
# CONFIGURATION
# ==========================

ORACLE_SID=ORCL                                       # Change to your database SID
ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1   # Change accordingly
BACKUP_DIR=/u01/backup/oracle                         # Directory to store backup files
LOG_DIR=/u01/backup/logs                              # Directory to store logs
EMAIL_TO="arnoldtayag@dbs.com"                        # Recipient of notification
HOSTNAME=$(mrsgdbsvr001)                              # Change to server hostname
DATE=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="$LOG_DIR/full_backup_$DATE.log"
RMAN_LOG="$LOG_DIR/rman_$DATE.log"
BACKUP_FILE="$BACKUP_DIR/full_backup_$DATE.bkp"
SUBJECT="[$HOSTNAME] Oracle Backup Status - $DATE"


# ==========================
# MAIN SECTION
# ==========================

# ====== Ensure directories exist ======
mkdir -p "$BACKUP_DIR" "$LOG_DIR"

export ORACLE_SID ORACLE_HOME PATH=$ORACLE_HOME/bin:$PATH

echo "==============================================" > "$LOG_FILE"
echo "Oracle Full Backup Started: $(date)" >> "$LOG_FILE"
echo "Database SID: $ORACLE_SID" >> "$LOG_FILE"
echo "==============================================" >> "$LOG_FILE"

rman target / <<EOF > "$RMAN_LOG" 2>&1
RUN {
  ALLOCATE CHANNEL ch1 DEVICE TYPE DISK FORMAT '$BACKUP_FILE';
  BACKUP DATABASE PLUS ARCHIVELOG;
  RELEASE CHANNEL ch1;
}
EXIT;
EOF

# ====== CHECK BACKUP RESULT ======
if grep -q "Finished backup" "$RMAN_LOG"; then
    STATUS="SUCCESS"
    MESSAGE="Oracle full backup completed successfully on $HOSTNAME at $(date). Backup file: $BACKUP_FILE"
else
    STATUS="FAILED"
    MESSAGE="Oracle backup failed on $HOSTNAME at $(date). Check log: $LOG_FILE"
fi

echo "Status: $STATUS" >> "$LOG_FILE"
echo "Details: $MESSAGE" >> "$LOG_FILE"
echo "==============================================" >> "$LOG_FILE"


# ==============================
# EMAIL NOTIFICATION
# ==============================
echo -e "$MESSAGE\n\nLog file attached: $LOG_FILE" | mail -s "$SUBJECT" "$EMAIL_TO"


# ==============================
# CLEANUP OLD BACKUPS (keep 7 days)
# ==============================
find "$BACKUP_DIR" -type f -mtime +7 -name "*.bkp" -exec rm -f {} \;
find "$LOG_DIR" -type f -mtime +7 -name "*.log" -exec rm -f {} \;

exit 0
