#!/usr/bin/ksh

echo "Input Parameter:" $1 $2

. /export/home1/oraclep/tspa/setenv_tspa.sh
if [ $? != 0 ]
then exit 1
fi

# ----------------------------------------------------------------------------------
# unset NLS_LANG is needed as setting it may cause core dump or unpredictable errors
# if SQL script contains special characters
# ----------------------------------------------------------------------------------
unset NLS_LANG

DDL_LOGFILE=`basename $0 .sh`_$TAG.log
export DDL_LOGFILE
$ORACLE_HOME/bin/sqlplus /nolog << ! > $DDL_DIR/$DDL_LOGFILE 2>&1
connect / as sysdba
whenever sqlerror exit sql.sqlcode
set echo on
set feedback on

alter system set session_cached_cursors=200 scope=spfile;

alter system set cursor_sharing=FORCE scope=both;

alter system set optimizer_index_cost_adj=10 scope=both;

alter system set filesystemio_options=SETALL scope=spfile;

exit
!
if [ $? != 0 ] || grep '^ORA-' $DDL_DIR/$DDL_LOGFILE
then
  echo "------------------------------------------------------"
  echo "$HOSTNAME ${ORACLE_SID} $BASENAME Error in running DDL"
  echo "------------------------------------------------------"
  $SCRIPT_DIR/mailx.sh "$HOSTNAME ${ORACLE_SID} $BASENAME Error in running DDL" \
                       $DDL_DIR/$DDL_LOGFILE
  exit 1
fi

if grep 'compilation errors' $DDL_DIR/$DDL_LOGFILE && \
   grep 'INVALID OBJECTS AFTER COMPILATION' $DDL_DIR/compile_obj.log
then
  echo "------------------------------------------------------"
  echo "$HOSTNAME ${ORACLE_SID} $BASENAME Error in running DDL"
  echo "------------------------------------------------------"
  $SCRIPT_DIR/mailx.sh "$HOSTNAME ${ORACLE_SID} $BASENAME Error in running DDL" \
                       $DDL_DIR/$DDL_LOGFILE
  exit 1
fi

# $SCRIPT_DIR/mailx.sh "$HOSTNAME ${ORACLE_SID} $BASENAME OK" $DDL_DIR/$DDL_LOGFILE
echo "------------------------------------"
echo "$HOSTNAME ${ORACLE_SID} $BASENAME OK"
echo "------------------------------------"
exit 0
