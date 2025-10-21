#!/usr/bin/env bash

# ===========================================================================
# Author: Arnold Aristotle Tayag
# Date created: 01-May-2015
# Description:
#   Get top 10 long-running queries on an Oracle instance and email the report
# Schedule: Adhoc
# Usage:
#   ./003_get_long_running_sql.sh -i 1 -r arnold@dbs.com -c "/ as sysdba"
# Requires:
#   sqlplus, and mailx/mail/sendmail for email
# Notes:
#   Works with either EZCONNECT (e.g., host:port/service), local OS authentication (/ as sysdba),
#   or a username/password
# Change Log:
#
# ===========================================================================

set -euo pipefail

# ---------------- Change based on your environment ----------------
CONNECT_STR=""              # e.g., "scott@//dbhost:1521/prod" or "/ as sysdba"
USER=""                     # If using username/password auth
ASK_PASS=0
INSTANCE_ID=""              # Required: gv$session.inst_id
OUTDIR="."
RECIPIENT="arnold@dbs.com"  # Required
SUBJECT_PREFIX="[Oracle Long-Running SQLs]"
ATTACH=1                    # attach file if mailx is available

usage() {
  cat <<'USAGE'
Usage:
  003_get_long_running_sql.sh -i INSTANCE_ID -r recipient@example.com
                          [-c "CONNECT_STR" | -u USER [-p]] [-o OUTDIR]
                          [--no-attach]

Options:
  -i INSTANCE_ID   Oracle instance ID (gv$session.inst_id).
  -r EMAIL         Recipient email address.
  -c CONNECT_STR   sqlplus connect string, e.g. "/ as sysdba" or "user@//host:1521/serv".
  -u USER          Username (will use password from prompt or ORACLE_PASSWORD env).
  -p               Prompt securely for password (ignored if -c "/ as sysdba").
  -o OUTDIR        Output directory (default: current dir).
  --no-attach      Inline the report in the email if mailx supports it; otherwise send as body.
  -h|--help        Show help.

Auth notes:
- Preferred for local admin: -c "/ as sysdba"
- For remote/EZCONNECT: -c "user@//host:port/service" (will prompt with -p or use ORACLE_PASSWORD).
- If using -u without -c, script will connect as "USER" to default tns/admin resolution.
USAGE
}

# --------------- Parse args ---------------
while (( "$#" )); do
  case "$1" in
    -i) INSTANCE_ID="$2"; shift 2;;
    -r) RECIPIENT="$2"; shift 2;;
    -c) CONNECT_STR="$2"; shift 2;;
    -u) USER="$2"; shift 2;;
    -p) ASK_PASS=1; shift;;
    -o) OUTDIR="$2"; shift 2;;
    --no-attach) ATTACH=0; shift;;
    -h|--help|help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

# --------------- Validate -----------------
if [[ -z "$INSTANCE_ID" || -z "$RECIPIENT" ]]; then
  echo "Error: -i INSTANCE_ID and -r RECIPIENT are required." >&2
  usage; exit 1
fi

mkdir -p "$OUTDIR"

# --------------- Build sqlplus connect ---------------
PASS=""
if [[ -n "$CONNECT_STR" ]]; then
  CONN="$CONNECT_STR"
else
  if [[ -n "$USER" ]]; then
    if (( ASK_PASS == 1 )); then
      read -r -s -p "Enter password for user '$USER': " PASS
      echo
      CONN="$USER/$PASS"
    else
      if [[ -n "${ORACLE_PASSWORD:-}" ]]; then
        CONN="$USER/$ORACLE_PASSWORD"
      else
        CONN="$USER"
      fi
    fi
  else
    # Fallback: try OS auth (dba)
    CONN="/ as sysdba"
  fi
fi

# --------------- Output file ---------------
TS="$(date +%Y%m%d_%H%M%S)"
OUTFILE="${OUTDIR%/}/long_running_sql_inst${INSTANCE_ID}_${TS}.txt"

# --------------- SQL to fetch top 10 ----------------
read -r -d '' SQL_QUERY <<'EOSQL'
SET PAGESIZE 50000 LINESIZE 300 LONG 100000 LONGCHUNKSIZE 100000 TRIMSPOOL ON TERMOUT OFF FEEDBACK OFF VERIFY OFF HEADING ON
COLUMN running_secs FORMAT 9999999999
COLUMN username     FORMAT A20
COLUMN machine      FORMAT A30
COLUMN program      FORMAT A35
COLUMN module       FORMAT A25
COLUMN event        FORMAT A35
COLUMN sql_id       FORMAT A15
COLUMN child        FORMAT 99999
COLUMN sid_serial   FORMAT A17
COLUMN inst_id      FORMAT 999
COLUMN plan_hash    FORMAT 9999999999
COLUMN sql_text     FORMAT A200 WORD_WRAPPED

PROMPT ===== Oracle Long-Running SQLs Report =====
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') AS report_time FROM dual;
PROMPT

-- Main query
WITH s AS (
  SELECT
    s.inst_id,
    s.sid||','||s.serial# AS sid_serial,
    s.sid,
    s.serial#,
    s.username,
    s.machine,
    s.program,
    s.module,
    s.event,
    s.sql_id,
    s.sql_child_number AS child,
    s.sql_exec_start,
    CASE
      WHEN s.sql_exec_start IS NOT NULL THEN ROUND((SYSDATE - s.sql_exec_start) * 86400)
      ELSE NVL(s.last_call_et, 0)
    END AS running_secs
  FROM gv$session s
  WHERE s.inst_id = :inst_id
    AND s.status = 'ACTIVE'
    AND s.type = 'USER'
    AND s.sql_id IS NOT NULL
)
SELECT
  s.inst_id,
  s.sid_serial,
  s.sql_id,
  s.child,
  s.running_secs,
  s.username,
  s.machine,
  s.program,
  s.module,
  s.event,
  a.plan_hash_value AS plan_hash,
  CASE
    WHEN LENGTH(a.sql_fulltext) <= 4000 THEN a.sql_fulltext
    ELSE SUBSTR(a.sql_fulltext,1,4000) || ' ...(truncated)'
  END AS sql_text
FROM s
LEFT JOIN gv$sqlarea a
  ON a.inst_id = s.inst_id
 AND a.sql_id  = s.sql_id
ORDER BY s.running_secs DESC
FETCH FIRST 10 ROWS ONLY;

PROMPT
PROMPT ---- Blocking info (if any) ----
COLUMN blocker FORMAT A30
SELECT
  s.inst_id,
  s.sid||','||s.serial# AS sid_serial,
  CASE
    WHEN s.blocking_session IS NOT NULL THEN s.blocking_session||','||s.blocking_session_serial#
    ELSE 'None'
  END AS blocker,
  s.event,
  s.wait_class,
  s.seconds_in_wait
FROM gv$session s
WHERE s.inst_id = :inst_id
  AND s.status = 'ACTIVE'
  AND s.type = 'USER'
  AND s.sql_id IS NOT NULL
  AND (s.blocking_session IS NOT NULL OR s.state='WAITING');

PROMPT
PROMPT ---- Notes ----
PROMPT running_secs uses SQL_EXEC_START if available, else LAST_CALL_ET (seconds since last call).
PROMPT Only ACTIVE user sessions are shown.
EOSQL

# --------------- Run sqlplus & spool ---------------
tmp_sql="$(mktemp)"
trap 'rm -f "$tmp_sql"' EXIT

cat > "$tmp_sql" <<EOF
SPOOL $OUTFILE
VARIABLE inst_id NUMBER
EXEC :inst_id := $INSTANCE_ID;
$SQL_QUERY
SPOOL OFF
EXIT
EOF

# Run
sqlplus -s "$CONN" @"$tmp_sql" >/dev/null || {
  echo "sqlplus execution failed. Check connectivity/privileges." >&2
  exit 1
}

# --------------- Email ----------------
SUBJECT="${SUBJECT_PREFIX} inst_id=${INSTANCE_ID} @ ${TS}"
BODY_INTRO=$(
cat <<EOF
Oracle long-running SQLs report

Instance ID : ${INSTANCE_ID}
Generated   : $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Output file : ${OUTFILE}

Top 10 currently running user SQLs ordered by running time (seconds).
EOF
)

send_with_mailx() {
  if command -v mailx >/dev/null 2>&1; then
    if (( ATTACH == 1 )); then
      mailx -s "$SUBJECT" -a "$OUTFILE" "$RECIPIENT" <<< "$BODY_INTRO"
    else
      mailx -s "$SUBJECT" "$RECIPIENT" <<< "$BODY_INTRO

$(cat "$OUTFILE")"
    fi
    return 0
  fi
  return 1
}

send_with_mail() {
  if command -v mail >/dev/null 2>&1; then
    mail -s "$SUBJECT" "$RECIPIENT" < "$OUTFILE"
    return 0
  fi
  return 1
}

send_with_sendmail() {
  if command -v sendmail >/dev/null 2>&1; then
    {
      echo "To: $RECIPIENT"
      echo "Subject: $SUBJECT"
      echo "MIME-Version: 1.0"
      BOUNDARY="=====BOUNDARY_$$"
      echo "Content-Type: multipart/mixed; boundary=\"$BOUNDARY\""
      echo
      echo "--$BOUNDARY"
      echo "Content-Type: text/plain; charset=UTF-8"
      echo "Content-Transfer-Encoding: 8bit"
      echo
      echo "$BODY_INTRO"
      echo
      echo "--$BOUNDARY"
      echo "Content-Type: text/plain; name=\"$(basename "$OUTFILE")\""
      echo "Content-Disposition: attachment; filename=\"$(basename "$OUTFILE")\""
      echo "Content-Transfer-Encoding: base64"
      echo
      base64 "$OUTFILE"
      echo "--$BOUNDARY--"
    } | sendmail -t
    return 0
  fi
  return 1
}

if send_with_mailx || send_with_mail || send_with_sendmail; then
  echo "Report saved to: $OUTFILE"
  echo "Email sent to:   $RECIPIENT"
else
  echo "Warning: No mailer found (mailx/mail/sendmail). Report saved to: $OUTFILE" >&2
  exit 2
fi
