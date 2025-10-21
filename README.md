# Oracle Admin Scripts

# Description
My repository of **automation scripts** for Oracle Database administration — including **full backups**, **incremental backups**, **AWR report generation**, performance tuning, and much more. These scripts are designed for **Linux environments** and can be easily integrated with **cron** 
or any commercial automation tool, such as Chef/Ansible/Puppet, for scheduled execution.

# Requirements
Before using these scripts, ensure the following:
   - ✅ Oracle Database 12c or higher  
   - ✅ `rman` and `sqlplus` available in `$PATH`  
   - ✅ Oracle environment variables correctly set (`ORACLE_SID`, `ORACLE_HOME`, etc.)  
   - ✅ Linux user has permission to write to backup and log directories
   - ✅ `mail` or `mailx` utility installed for email notifications  

# Environment Variables
Make sure the following are defined either in your environment or inside each script:
   - export ORACLE_SID=ORCL
   - export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
   - export PATH=$ORACLE_HOME/bin:$PATH

# Directory Structure
This is the recommended structure for backups, logs, and reports:
   - /u01/
   - ├── backup/
      - ├── oracle/               # Full and incremental backup files
      - ├── logs/                 # Log files from scripts
      - └── awr_reports/          # Generated AWR HTML reports
   - └── scripts/
      - ├── oracle_full_backup.sh
      - ├── oracle_incremental_backup.sh
      - ├── oracle_awr_report.sh
      - └── etc.

# Repository Contents (for updating)

| Script Name                          | Description                                                                                                   |
|--------------------------------------|---------------------------------------------------------------------------------------------------------------|
| `oracle_full_backup.sh`              | Performs a **full RMAN database backup** with logs, email notifications, and automated cleanup                |
| `oracle_incremental_backup.sh`       | Runs an **incremental RMAN Level 1 backup** every few hours, also with email alerts and log management        |
| `oracle_awr_report.sh`               | Generates **AWR (Automatic Workload Repository)** reports for performance analysis and reports                |
