@echo off
setlocal enabledelayedexpansion

:: ================================
:: CONFIGURATION
:: ================================
set ORACLE_USER=myuser
set ORACLE_PASS=mypass
set ORACLE_DB=//localhost:1521/orcl

:: List of tables to exclude (comma-separated, UPPERCASE)
set EXCLUDE_LIST=TABLE_TO_SKIP1,TABLE_TO_SKIP2

:: Output directories
set DIR_SEQ=01_sequences
set DIR_TAB=02_tables
set DIR_TRG=03_trigs
set DIR_DATA=04_data
set DIR_CONS=05_cons
set DIR_VIEWS=06_views
set DIR_OTHER=07_other
set DIR_STR=04_data\str_loader

:: Make directories
for %%D in (%DIR_SEQ% %DIR_TAB% %DIR_TRG% %DIR_DATA% %DIR_CONS% %DIR_VIEWS% %DIR_OTHER% %DIR_STR%) do (
    if not exist %%D mkdir %%D
)

:: ================================
:: Export sequences
:: ================================
for /f %%S in ('sqlplus -S %ORACLE_USER%/%ORACLE_PASS%@%ORACLE_DB% "set heading off feedback off pagesize 0; select sequence_name from user_sequences; exit;"') do (
    sqlplus -S %ORACLE_USER%/%ORACLE_PASS%@%ORACLE_DB% ^
    "set heading off feedback off pagesize 0 long 999999;
     spool %DIR_SEQ%\%%S.sql;
     select dbms_metadata.get_ddl('SEQUENCE','%%S') from dual;
     spool off;
     exit;"
)

:: ================================
:: Export tables (DDL only)
:: ================================
for /f %%T in ('sqlplus -S %ORACLE_USER%/%ORACLE_PASS%@%ORACLE_DB% "set heading off feedback off pagesize 0; select table_name from user_tables; exit;"') do (
    sqlplus -S %ORACLE_USER%/%ORACLE_PASS%@%ORACLE_DB% ^
    "begin
       dbms_metadata.set_transform_param(dbms_metadata.session_transform,'CONSTRAINTS',false);
       dbms_metadata.set_transform_param(dbms_metadata.session_transform,'REF_CONSTRAINTS',false);
     end;
     /
     spool %DIR_TAB%\%%T.sql;
     select dbms_metadata.get_ddl('TABLE','%%T') from dual;
     spool off;
     exit;"
)

:: ================================
:: Export constraints, triggers, views, other objects
:: (same as previous script)
:: ================================
:: [omitted for brevity, same logic as before]

:: ================================
:: Export data excluding EXCLUDE_LIST and OCC_STR_DATA%
:: ================================
for /f %%D in ('sqlplus -S %ORACLE_USER%/%ORACLE_PASS%@%ORACLE_DB% ^
"set heading off feedback off pagesize 0;
 select table_name from user_tables
 where table_name not in (%EXCLUDE_LIST%)
   and table_name not like 'OCC_STR_DATA%';
 exit;"') do (
    sqlplus -S %ORACLE_USER%/%ORACLE_PASS%@%ORACLE_DB% @"datatype_handler.sql"
)

:: ================================
:: Export OCC_STR_DATA tables as .LDR
:: ================================
for /f %%S in ('sqlplus -S %ORACLE_USER%/%ORACLE_PASS%@%ORACLE_DB% ^
"set heading off feedback off pagesize 0; select table_name from user_tables where table_name like 'OCC_STR_DATA%'; exit;"') do (
    echo Generating SQL*Loader control for %%S
    echo LOAD DATA > %DIR_STR%\%%S.ctl
    echo INFILE * >> %DIR_STR%\%%S.ctl
    echo INTO TABLE %%S >> %DIR_STR%\%%S.ctl
    echo FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' >> %DIR_STR%\%%S.ctl
    echo (all columns need to be listed manually) >> %DIR_STR%\%%S.ctl

    sqlplus -S %ORACLE_USER%/%ORACLE_PASS%@%ORACLE_DB% ^
      "set colsep ',' head off pagesize 0 feedback off trimspool on linesize 32767; spool %DIR_STR%\%%S.csv; select * from %%S; spool off;"
)

:: ================================
:: Generate master rebuild script
:: ================================
(
echo @01_sequences\all_sequences.sql
echo @02_tables\all_tables.sql
echo @03_trigs\all_triggers.sql
echo @05_cons\all_constraints.sql
echo @06_views\all_views.sql
echo @07_other\all_other.sql
echo @04_data\all_data.sql
) > rebuild_all.sql

echo Backup complete!
pause
