#!/bin/ksh

echo "Input Parameter:" $1 $2 $3

######################################################
#
#Expand tablespace
#
#PARM1=Database Name
#PARM2=Tablespace Name
#PARM3=datafile mountpoint
#PARM4=Size to increase (in MB, filesystem free space is the limit now)
######################################################

#!/usr/bin/ksh

echo "Input Parameter:" $1 $2 $3 $4

# ------------------------------------------------------------------
# IMPORTANT NOTES :
# - BTS must inform DBA before triggering this job
# - Amend the file system df command according to the platform
# - Set the file system threshold as required (default : 10 GB)
# ------------------------------------------------------------------

. /export/home1/oraclep/tsph/setenv_tsph.sh
if [ $? != 0 ]
then exit 1
fi

# ----------------------------------------------------------------------------------
# unset NLS_LANG is needed as setting it may cause core dump or unpredictable errors
# if SQL script contains special characters
# ----------------------------------------------------------------------------------
unset NLS_LANG

# -----------------------------------------------------------------------------------------
# This script will accept 4 input paramaters:
# 1.  Database name
# 2.  Tablespace name
# 3.  Filesystem containing the Datafiles. (e.g. /poradata1, /poradata4)
# 4.  Additional size to add to tablespace in MBytes
#       User input ignored for TB3 which will always default to 4097 MB
#       Min size : 1000 MB for TB2/IX2
#       Max size : 1000 MB for TB1/IX1
#                  4000 MB for TB2/IX2
#                  4000 MB for other tablespace
#
# If the size of the last datafile for the tablespace is less than the max
# allowable datafile size, it will be resize to the maximum value for per datafile.
#
# If the size of the last datafile for the tablespace is equal or more than the
# max allowable dafile# size, a new datafile will be added.
#
# DEFINED VARIABLES :
#       $TSNAME = tablespace name
#       $DBDIR  = datafiles mount point
#
# This script take the following assumptions :
# - Applicable only for expansion of application tablespaces.
# - Datafile location / name : $DBDIR/${ORACLE_SID}/dbf/$TSNAME_f*.dbf
# - File system threshold and minimum disk space required on disk as defined above
#
# Job will abend if the available disk space is less than the threshold defined.
# -----------------------------------------------------------------------------------------

DBDIR=`echo $3`
export DBDIR

if ! test -d $DBDIR
then
  echo "---------------------------------------------------"
  echo "$HOSTNAME ${ORACLE_SID} Invalid Filesystem - $DBDIR"
  echo "---------------------------------------------------"
  exit 1
fi

# For HP-UX and IBM AIX, change df command to df -kP
# For Sun Solaris, change df command to df -k

DISK_THRESHOLD_KB=`expr $4 \* 1024 + 10000000`

df -k | grep $DBDIR | while read FILESYSTEM KBYTES USED AVAIL CAPACITY MOUNTED_ON
do
   FREE_KB=`echo $AVAIL | tr -d '%'`
   if [ ${FREE_KB} -lt ${DISK_THRESHOLD_KB} ] && [ ${DBDIR} = ${MOUNTED_ON} ]
   then
     echo "-----------------------------------------------------------------------"
     echo "$HOSTNAME ${ORACLE_SID} Tablespace expansion not allowed."
     echo "File system free space is less than ${DISK_THRESHOLD_KB} KB"
     echo "-----------------------------------------------------------------------"
     exit 1
   fi
done

# ---------------------------
# VERIFY TABLESPACE NAME
# ---------------------------

TSNAME=`echo $2|tr '[:upper:]' '[:lower:]'`
export TSNAME

if ! test -f $DBDIR/${ORACLE_SID}/dbf/*${TSNAME}_f*.dbf
then
  echo "---------------------------------------------------------"
  echo "$HOSTNAME ${ORACLE_SID} Invalid Tablespace Name - $TSNAME"
  echo "---------------------------------------------------------"
  exit 1
fi

TSNAME=`echo $2|tr '[:lower:]' '[:upper:]'`
export TSNAME

len=`echo $TSNAME | wc -c`
len=`expr $len - 1 - 2`

TSNAME2=`echo $TSNAME | cut -c $len-`
export TSNAME2

# ---------------------------
# TABLESPACE SIZE TO ADD IN MBYTES
# ---------------------------

TSSIZE=`echo $4`
export TSSIZE

# ------------------------------
# DEFINE DATAFILE SIZE IN MBYTES
# ------------------------------

DBFILESIZE=16000
export DBFILESIZE

DDL_LOGFILE=`basename $0 .sh`_$TAG.log
export DDL_LOGFILE

$ORACLE_HOME/bin/sqlplus -S /nolog << ! > $DDL_DIR/$DDL_LOGFILE 2>&1
connect / as sysdba
whenever sqlerror exit sql.sqlcode

set linesize 200
set pagesize 0
set feedback on
set echo on
set trimspool on
set serveroutput on
DECLARE
        v_add_size      number := ${TSSIZE};
        v_maxfile_size  number := ${DBFILESIZE};
        v_target_filesize       number := ${DBFILESIZE};
        v_newfileid     number;
        v_tbsname       VARCHAR2(80) := '${TSNAME}';
BEGIN
        for v_file_info in (
select FILE_NAME, FILE_ID, CEIL(df.BYTES/1024/1024) "SZMB"
from dba_data_files df
where CEIL(df.BYTES/1024/1024) < v_maxfile_size
and df.tablespace_name = v_tbsname
ORDER BY TO_NUMBER(SUBSTR(FILE_NAME,INSTR(FILE_NAME,'_f',1)+2,INSTR(FILE_NAME,'.',1)-INSTR(FILE_NAME,'_f',1)-2)))
        loop
                dbms_output.put_line(v_file_info.file_name || ':');
                dbms_output.put_line('Current size: ' || v_file_info.SZMB || 'M' );
                IF v_add_size+v_file_info.SZMB > v_maxfile_size THEN
                  v_target_filesize := v_maxfile_size;
                ELSE
                  v_target_filesize := v_add_size+v_file_info.SZMB;
                END IF;
                IF v_file_info.SZMB < v_target_filesize THEN
                  execute immediate 'ALTER DATABASE DATAFILE ''' || v_file_info.file_name || ''' RESIZE ' || v_target_filesize|| 'M';
                  dbms_output.put_line('ALTER DATABASE DATAFILE ''' || v_file_info.file_name || ''' RESIZE ' || v_target_filesize|| 'M;');
                  v_add_size := v_add_size - (v_target_filesize - v_file_info.SZMB);
                  dbms_output.put_line('Remaining size to add: '||v_add_size||'M;');
                END IF;
		EXIT WHEN v_add_size <= 0;
        end loop;

        WHILE v_add_size > 0
        LOOP
                select MAX(TO_NUMBER(SUBSTR(FILE_NAME,INSTR(FILE_NAME,'_f',1)+2,INSTR(FILE_NAME,'.',1)-INSTR(FILE_NAME,'_f',1)-2)))+1
                INTO v_newfileid
                from DBA_DATA_FILES
                WHERE TABLESPACE_NAME = v_tbsname;

                IF v_add_size > v_maxfile_size THEN
                  v_target_filesize := v_maxfile_size;
                ELSE
                  v_target_filesize := v_add_size;
                END IF;
			dbms_output.put_line('alter tablespace '||v_tbsname||' add datafile ''$DBDIR/$ORACLE_SID/dbf/'||lower('$TSNAME')||'_f'||v_newfileid||'.dbf'' size '||v_target_filesize||'m');
                execute immediate 'alter tablespace '||v_tbsname||' add datafile ''$DBDIR/$ORACLE_SID/dbf/'||lower('$TSNAME')||'_f'||v_newfileid||'.dbf'' size '||v_target_filesize||'m';
                v_add_size := v_add_size - v_target_filesize;
        END LOOP;
END;
/
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

# $SCRIPT_DIR/mailx.sh "$HOSTNAME ${ORACLE_SID} $BASENAME OK" $DDL_DIR/$DDL_LOGFILE
echo "------------------------------------"
echo "$HOSTNAME ${ORACLE_SID} $BASENAME OK"
echo "------------------------------------"
exit 0

