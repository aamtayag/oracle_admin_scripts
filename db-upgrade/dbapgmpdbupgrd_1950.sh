#!/bin/ksh

##########################################################################
### 
### Oracle upgrade script from 19.4 to 19.5
###
### Pre-requisite checks:
###    1. Make sure that no DBs and listeners are running
###    2. Make sure that /poracle has enough disk space
###
##########################################################################

export HOME1=/export/home1/oraclep/dba

$HOME1/dbora stop
$HOME1/lsnrstop

export TAG=`date +"%Y%m%d_%H%M%S"`

LOGFILE=`basename $0 .sh`_${TAG}.log
export LOGFILE

exec >> $LOGFILE 2>&1

rm /poracle/PatchSearch.xml

echo "Unzipping Oracle 19.5 patch..." 
unzip /poracle/p30446054_190000_SOLARIS64.zip
if [ $? != 0 ]; then
    exit 1
fi

echo "Backing up 1900 home..."
tar -czvf /poracle/1900_bkup_${TAG}.tar.gz /poracle/1900
#if [ $? != 0 ]; then
#    exit 1
#fi

mkdir -p /poracle/1900/sqldeveloper/sqldeveloper/lib
touch /poracle/1900/sqldeveloper/sqldeveloper/lib/osdt_cert.jar
cd 30446054

/poracle/1900/OPatch/opatch prereq CheckConflictAgainstOHWithDetail -ph ./
if [ $? != 0 ]; then
    exit 1
fi

/poracle/1900/OPatch/opatch apply -silent

exit 0
