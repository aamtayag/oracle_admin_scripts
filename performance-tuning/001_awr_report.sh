#!/bin/bash

# ===========================================================================
# Author: Arnold Aristotle Tayag
# Date created: 01-May-2015
# Description:
#   Oracle AWR Report Generator
#   Generates an AWR report for a specific Oracle instance
# Schedule: Adhoc
# Change Log:
#
# ===========================================================================


# ==========================
# CONFIGURATION
# ==========================

ORACLE_SID=ORCL                                         # Change to your Oracle SID
ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1     # Adjust Oracle Home path
AWR_DIR=/u01/backup/awr_reports                         # Directory to save AWR reports
HOSTNAME=$(mvndbsvr010)                                 # Change to server hostname
DATE=$(date +"%Y-%m-%d_%H-%M-%S")
AWR_REPORT_FILE="$AWR_DIR/awr_report_${ORACLE_SID}_$DATE.html"
LOG_FILE="$AWR_DIR/awr_report_${ORACLE_SID}_$DATE.log"
EMAIL_TO="arnoldtayag@dbs.com"
SUBJECT="[$HOSTNAME] AWR Report for $ORACLE_SID - $DATE"


# ==========================
# MAIN SECTION
# ==========================

export ORACLE_SID ORACLE_HOME PATH=$ORACLE_HOME/bin:$PATH
mkdir -p "$AWR_DIR"

echo "===================================================" > "$LOG_FILE"
echo "Generating AWR Report for instance: $ORACLE_SID" >> "$LOG_FILE"
echo "Date: $(date)" >> "$LOG_FILE"
echo "Output File: $AWR_REPORT_FILE" >> "$LOG_FILE"
echo "===================================================" >> "$LOG_FILE"

# ====== SQLPLUS COMMAND TO GENERATE AWR REPORT ======
sqlplus -s / as sysdba <<EOF >> "$LOG_FILE" 2>&1
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
COLUMN begin_snap NEW_VALUE begin_snap_id
COLUMN end_snap NEW_VALUE end_snap_id

-- Get the last two snapshot IDs
SELECT MAX(snap_id)-1 AS begin_snap, MAX(snap_id) AS end_snap FROM dba_hist_snapshot;

SPOOL $AWR_REPORT_FILE
SELECT output FROM TABLE(dbms_workload_repository.awr_report_html(
        (SELECT dbid FROM v\$database),
        (SELECT instance_number FROM v\$instance),
        &begin_snap,
        &end_snap
));
SPOOL OFF
EXIT;
EOF

# ====== CHECK IF REPORT WAS GENERATED ======
if [ -f "$AWR_REPORT_FILE" ] && [ -s "$AWR_REPORT_FILE" ]; then
    STATUS="SUCCESS"
    MESSAGE="AWR report generated successfully for instance $ORACLE_SID at $(date). File: $AWR_REPORT_FILE"
else
    STATUS="FAILED"
    MESSAGE="AWR report generation failed for instance $ORACLE_SID at $(date). Check log: $LOG_FILE"
fi

echo "Status: $STATUS" >> "$LOG_FILE"
echo "Details: $MESSAGE" >> "$LOG_FILE"
echo "===================================================" >> "$LOG_FILE"


# ==============================
# EMAIL NOTIFICATION
# ==============================
if [ "$STATUS" == "SUCCESS" ]; then
    echo -e "$MESSAGE\n\nReport: $AWR_REPORT_FILE" | mail -s "$SUBJECT" "$EMAIL_TO"
else
    echo -e "$MESSAGE\n\nCheck log file for details: $LOG_FILE" | mail -s "$SUBJECT - FAILED" "$EMAIL_TO"
fi

exit 0
