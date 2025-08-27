# Automating Comprehensive Database Backups

## Overview
- Typically database objects are exported manually: a folder per object(s) as separate files,and as a single file for ease of rebuild
- Update the ```backup_schema.ps1``` directory to where you want the db backup to occur
- Recommended for data managers with an understanding the difference for db exports between separate vs single files, and DDL vs DATA, different ways to export - ldr, insert, csv, etc.

## Prerequisites
- Windows 10 or higher (tested with batch .bat scripts).
- Any Windows Server version that supports SQL*Plus (e.g., 2016, 2019).
- Alternatively, Linux/Unix (requires rewriting .bat to .sh and adjusting paths).

**Instructions**
1. Download <code>backup_schema.ps1</code> and all supporting .sql scripts: <code>export_sequence.sql </code> <code>export_table.sql </code> <code>export_trigger.sql </code> <code>export_data.sql </code> <code>export_constraint.sql </code> <code>export_view.sql </code> <code>export_other.sql </code> in the same directory  
   (*does not have to be where you want the backup to go*)
3. Update the user/schema, password, databse connection, and output directory  
   (*can also include list of tables to exclude if desired  
     comment out the OCC_STR_DATA loader section for a quicker backup*)
5. Open windows PowerShell
6. Change the directory to where you placed <code>backup_schema.ps1</code> and supporting scripts
     - ex:  <code> cd C:\Users\Brighton.Hedger\Desktop\backup_test </code>
7. Run the following line:
     - <code> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process </code>
8. Run the script:
     - <code> ./backup_schema.ps1 </code>


**Oracle Backup/Restore Script – System Requirements**

**1. Operating System**

*   Windows 10 or higher
*   Windows Server 2016/2019 supported
*   For Linux/Unix, scripts must be converted from .bat to .sh

**2. Oracle Client**

*   SQL\*Plus installed and accessible from the command line
*   Recommended: Oracle Instant Client (Basic + SQL\*Plus packages)
*   Version must match Oracle DB version (e.g., 19c client for 19c DB)
*   Add Oracle Instant Client directory to PATH environment variable

**3. Oracle Database**

*   Network-accessible from the machine running the script
*   User account privileges:
    *   SELECT ANY TABLE
    *   SELECT ANY SEQUENCE
    *   SELECT ANY TRIGGER, SELECT ANY VIEW, SELECT ANY PROCEDURE, SELECT ANY OBJECT
    *   EXECUTE on DBMS\_METADATA
*   Recommended: dedicated backup user with read-only access

**4. Disk Space**

*   Depends on database size
*   Ensure enough free space for:
    *   01\_sequences
    *   02\_tables
    *   03\_trigs
    *   04\_data (including OCC\_STR\_DATA CSVs)
    *   05\_cons
    *   06\_views
    *   07\_other
*   Large CLOB-heavy tables may require GBs of space

**5. SQL\*Plus Limits**

*   Max VARCHAR2 in PL/SQL: 32,767 characters
*   CLOB export settings:
    *   LONG 2000000
    *   LONGCHUNKSIZE 2000000
    *   LINESIZE 32767
*   Adjust values for extremely large CLOBs

**6. Other Software**

*   Text editor (VS Code, Notepad++, etc.)
*   Optional: SQL Developer for verification

**Recommendations**

1.  Test first on a small subset of tables
2.  Avoid running on production if performance could be affected
3.  Ensure CSV settings for OCC\_STR\_DATA handle special characters properly (OPTIONALLY ENCLOSED BY '\"')

## Version Control Platform
- Git

## License
See the [LICENSE.md](./LICENSE.md) for details

## Disclaimer
This repository is a scientific product and is not official communication of the National Oceanic and Atmospheric Administration, or the United States Department of Commerce. All NOAA GitHub project code is provided on an ‘as is’ basis and the user assumes responsibility for its use. Any claims against the Department of Commerce or Department of Commerce bureaus stemming from the use of this GitHub project will be governed by all applicable Federal law. Any reference to specific commercial products, processes, or services by service mark, trademark, manufacturer, or otherwise, does not constitute or imply their endorsement, recommendation or favoring by the Department of Commerce. The Department of Commerce seal and logo, or the seal and logo of a DOC bureau, shall not be used in any manner to imply endorsement of any commercial product or activity by DOC or the United States Government.
