#!/bin/bash

# ===========================================================================
# Author: Arnold Aristotle Tayag
# Date created: 01-May-2015
# Description:
#   Generate Oracle SQL execution plan & metrics for a given SQL_ID,
#   then email the name of the generated report file
# Schedule: Adhoc
# Usage:   ./002_get_sql_execplan.sh <SQL_ID> <ORACLE_SID> [email@domain]
# Notes:   Requires sqlplus and oraenv; run as a user with SYSDBA or proper views access
# Change Log:
#
# ===========================================================================

set -euo pipefail

# ====== Args & usage ======
usage() {
  echo "Usage: $0 <SQL_ID> <ORACLE_SID> [EMAIL_TO]"
  echo "Example: $0 4p1x5m9z6p8fyx ORCL you@example.com"
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage; exit 1
fi

SQL_ID="$1"
ORACLE_SID="$2"
# EMAIL_TO="${3:-}"   # optional
EMAIL_TO="arnoldtayag@dbs.com"


# ====== Prep ======
DATESTAMP="$(date '+%Y%m%d_%H%M%S')"
OUTFILE="/tmp/sqlplan_${SQL_ID}_${DATESTAMP}.txt"

# Preferred mailer; will fall back to 'mail' if available
MAILER=""
if command -v mailx >/dev/null 2>&1; then
  MAILER="mailx"
elif command -v mail >/dev/null 2>&1; then
  MAILER="mail"
fi

# ====== Oracle env ======
export ORACLE_SID
export ORAENV_ASK=NO

# Try common oraenv locations; ignore errors if not present
if [[ -x /usr/local/bin/oraenv ]]; then
  . /usr/local/bin/oraenv >/dev/null 2>&1 || true
elif [[ -x /usr/bin/oraenv ]]; then
  . /usr/bin/oraenv >/dev/null 2>&1 || true
fi

if ! command -v sqlplus >/dev/null 2>&1; then
  echo "ERROR: sqlplus not found in PATH. Ensure Oracle client is installed and oraenv was sourced."
  exit 2
fi

# ====== Run SQLPlus ======
# Using / as sysdba here. If you prefer a normal user, replace with: sqlplus -s user/pass@tns
# DBMS_XPLAN.DISPLAY_CURSOR uses ALLSTATS LAST for actual execution stats (if cursor was run with stats).
# LONG is increased for full plan + SQL text; LINESIZE widened; timing OFF for clean output.
set +e
sqlplus -s / as sysdba >"$OUTFILE" <<SQL
SET ECHO OFF FEEDBACK OFF HEADING ON LINES 300 PAGES 500 LONG 200000 LONGCHUNKSIZE 200000 TRIMSPOOL ON
PROMPT ==========================================================================
PROMPT SQL Execution Plan and Metrics for SQL_ID: ${SQL_ID}
PROMPT Generated on: $(date)
PROMPT ORACLE_SID: ${ORACLE_SID}
PROMPT ==========================================================================

PROMPT
PROMPT >> SQL Text (v\$sql):
COLUMN sql_fulltext FORMAT A200
SELECT sql_fulltext FROM v\$sql WHERE sql_id = '${SQL_ID}' AND child_number = (
  SELECT MIN(child_number) FROM v\$sql WHERE sql_id = '${SQL_ID}'
);
PROMPT

PROMPT >> Execution Plan (DBMS_XPLAN.DISPLAY_CURSOR, ALLSTATS LAST):
SET SERVEROUTPUT ON
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR('${SQL_ID}', NULL, 'BASIC +NOTE +ALIAS +PROJECTION +PREDICATE +PEEKED_BINDS +ALLSTATS LAST'));
PROMPT

PROMPT >> Performance Metrics (v\$sql):
COLUMN executions     FORMAT 999,999,999
COLUMN elapsed_time   FORMAT 999,999,999,999
COLUMN cpu_time       FORMAT 999,999,999,999
COLUMN buffer_gets    FORMAT 999,999,999,999
COLUMN disk_reads     FORMAT 999,999,999,999
COLUMN rows_processed FORMAT 999,999,999,999
SELECT sql_id, child_number, plan_hash_value,
       executions, elapsed_time, cpu_time, buffer_gets, disk_reads, rows_processed,
       TO_CHAR(last_load_time,'YYYY-MM-DD HH24:MI:SS') AS last_load_time
FROM v\$sql
WHERE sql_id = '${SQL_ID}'
ORDER BY child_number;

PROMPT
PROMPT >> Note:
PROMPT - If the plan shows only EXPLAIN PLAN without ALLSTATS, the cursor may not have been run with stats gathering.
PROMPT - If no rows return from v\$sql, the cursor may have aged out of the shared pool.
SQL
rc=\$?
set -e

if [[ \$rc -ne 0 ]]; then
   echo "ERROR: sqlplus returned non-zero exit status (\$rc). Check \$OUTFILE for details."
   exit \$rc
fi

# -------- Post-checks -------------------------------------------------------
if [[ ! -s "\$OUTFILE" ]]; then
   echo "ERROR: Output file not created or empty: \$OUTFILE"
   exit 3
fi

echo "SUCCESS: Report written to \$OUTFILE"

# -------- Email (filename) --------------------------------------------------
if [[ -n "\$EMAIL_TO" && -n "\$MAILER" ]]; then
    SUBJECT="Oracle SQL Plan Report for SQL_ID=\$SQL_ID (SID=\$ORACLE_SID)"
    BODY=\$(cat <<EOF
      Hello,

      The execution plan and metrics report for:
        SQL_ID: \$SQL_ID
        SID:    \$ORACLE_SID

      Report file (on host): \$OUTFILE
      Generated:             \$(date)

      Regards,
      Oracle Automation Script
      EOF
    )
    # Send email (no attachment; just the filename as requested)
    printf "%s\n" "\$BODY" | \$MAILER -s "\$SUBJECT" "\$EMAIL_TO" || true

    # If you prefer to ATTACH the report, uncomment the block below (requires mailx that supports -a):
    # printf "%s\n" "\$BODY" | \$MAILER -s "\$SUBJECT" -a "\$OUTFILE" "\$EMAIL_TO" || true
else
    if [[ -n "\$EMAIL_TO" && -z "\$MAILER" ]]; then
      echo "NOTE: Email requested to \$EMAIL_TO but no 'mailx'/'mail' found in PATH. Skipping email."
    fi
fi
