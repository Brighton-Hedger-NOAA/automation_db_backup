# ================================
# CONFIGURATION
# ================================

$outputDirectory = "T:\DataManagement\_Backups\Oracle\GISD_INTERIM\2025\20250822"
# ^^CHANGE AS NEEDED^^

$oracleUser = "SCHEMA/USERNAME"
$oraclePass = "MY_PASSWORD"
$oracleDb = "//HOSTNAME:PORT/SERVICENAME"

$sqlplusPath = "sqlplus"

# list of tables to exclude if wanted
$excludeList = "'TABLE_TO_SKIP1','TABLE_TO_SKIP2'"

# output Directories
$baseDir = $outputDirectory
$dirSeq = Join-Path $baseDir "01_seq"
$dirTab = Join-Path $baseDir "02_tables"
$dirTrg = Join-Path $baseDir "03_trigs"
$dirData = Join-Path $baseDir "04_data"
$dirCons = Join-Path $baseDir "05_cons"
$dirViews = Join-Path $baseDir "06_views"
$dirOther = Join-Path $baseDir "07_other"
$dirStr = Join-Path $baseDir "04_data\str_loader"
$dirCombined = Join-Path $baseDir "single_files"

# connect to databse
$sqlConnect = "CONNECT $oracleUser/$oraclePass@$oracleDb"

# create Directories
Write-Host "Creating output directories..." -ForegroundColor Cyan
$dirsToCreate = @($dirSeq, $dirTab, $dirTrg, $dirData, $dirCons, $dirViews, $dirOther, $dirStr, $dirCombined)
foreach ($dir in $dirsToCreate) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
}

# function to run SQL queries and return the result
function Get-SqlResult {
    param($Query)
    $connectionString = "$oracleUser/$oraclePass@$oracleDb"
    $sqlScript = @"
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 TERMOUT OFF TRIMOUT ON TRIMSPOOL ON
$Query
/
EXIT;
"@
    $result = $sqlScript | & $sqlplusPath -S -L $connectionString
    return $result | Where-Object { $_.Trim() -ne '' }
}

# function to run side scripts for main db objects (seq, tab, trig, data, view, cons)
function Export-DbObject {
    param($HelperScript, $ObjectName, $OutputFile)
    $sqlScript = @"
$sqlConnect
@$HelperScript '$ObjectName'
exit;
"@
    $sqlScript | & $sqlplusPath -S /nolog | Set-Content -Path $OutputFile
}
# function to run side script for all other db objects (functions, packages, etc)
function Export-GenericObject {
    param($ObjectType, $ObjectName, $OutputFile)
    $sqlScript = @"
$sqlConnect
@export_other.sql '$ObjectType' '$ObjectName'
exit;
"@
    $sqlScript | & $sqlplusPath -S /nolog | Set-Content -Path $OutputFile
}


# ================================
# Exporting  Objects
# ================================

# export seq
Write-Host "Exporting sequences..." -ForegroundColor Cyan
$sequences = Get-SqlResult "select sequence_name from user_sequences;"
foreach ($sequence in $sequences) {
    if ($sequence.Trim()) {
        Write-Host " - Exporting sequence $sequence"
        Export-DbObject "export_sequence.sql" $sequence (Join-Path $dirSeq "$sequence.sql")
    }
}

# export tab
Write-Host "Exporting table definitions..." -ForegroundColor Cyan
$tables = Get-SqlResult "select table_name from user_tables;"
foreach ($table in $tables) {
    if ($table.Trim()) {
        Write-Host " - Exporting table $table"
        Export-DbObject "export_table.sql" $table (Join-Path $dirTab "$table.sql")
    }
}

# export trig
Write-Host "Exporting triggers..." -ForegroundColor Cyan
$triggers = Get-SqlResult "select trigger_name from user_triggers;"
foreach ($trigger in $triggers) {
    if ($trigger.Trim()) {
        Write-Host " - Exporting trigger $trigger"
        Export-DbObject "export_trigger.sql" $trigger (Join-Path $dirTrg "$trigger.sql")
    }
}

# export data
Write-Host "Exporting data..." -ForegroundColor Cyan
$dataTables = Get-SqlResult "select table_name from user_tables where table_name not in ($excludeList) and table_name not like 'OCC_STR_DATA%' and table_name not like 'BIN$%';"
foreach ($table in $dataTables) {
    Write-Host " - Exporting data for $table"
    $outputFile = Join-Path $dirData "$($table)_DATA_TABLE.sql"
    Export-DbObject "export_data.sql" $table $outputFile
}

# export OCC_STR_DATA tables as .ldr's
Write-Host "Exporting large string data tables..." -ForegroundColor Cyan
$strTables = Get-SqlResult "select table_name from user_tables where table_name like 'OCC_STR_DATA%';"
foreach ($table in $strTables) {
    if ($table.Trim()) {
        $cleanTableName = $table.Trim()
        Write-Host " - Generating SQL*Loader files for $cleanTableName"
        $columnQuery = "SELECT column_name || ';' || data_type FROM user_tab_columns WHERE table_name = '$cleanTableName' ORDER BY column_id"
        $columnsAndTypes = Get-SqlResult $columnQuery
        $columnListEntries = @()
        foreach ($line in $columnsAndTypes) {
            $parts = $line.Split(';', 2)
            if ($parts.Count -eq 2) {
                $columnName = $parts[0].Trim()
                $dataType = $parts[1].Trim()
                if ($dataType -eq "DATE") {
                    $columnListEntries += "  `"$columnName`" DATE ""DD-MON-YY"""
                }
                else {
                    $columnListEntries += "  `"$columnName`""
                }
            }
        }
        $columnList = "(" + ($columnListEntries -join ",`r`n") + "`r`n)"
        $ldrFilePath = Join-Path $dirStr "$cleanTableName.ldr"
        $ctlFilePath = Join-Path $dirStr "$cleanTableName.ctl"
        $ctlContent = @"
OPTIONS (SKIP=0, ERRORS=-1, ROWS=1000, BINDSIZE=256000, READSIZE=256000)
LOAD DATA
INFILE '$ldrFilePath' "str '{EOL}'"
APPEND
CONTINUEIF NEXT(1:1) = '#'
INTO TABLE "$cleanTableName"
FIELDS TERMINATED BY '|' OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
$columnList
"@
        Set-Content -Path $ctlFilePath -Value $ctlContent
        $ldrScript = @"
CONNECT $oracleUser/$oraclePass@$oracleDb
set colsep '|' head off pagesize 0 feedback off trimspool on linesize 32767;
spool "$ldrFilePath"
select * from $cleanTableName;
spool off;
exit;
"@
        $ldrScript | & $sqlplusPath -S /nolog | Out-Null
    }
}

# export cons
Write-Host "Exporting constraints..." -ForegroundColor Cyan
$tablesWithConstraints = Get-SqlResult "SELECT DISTINCT uc.table_name FROM user_constraints uc JOIN user_tables ut ON uc.table_name = ut.table_name WHERE uc.constraint_name NOT LIKE 'BIN$%';"

foreach ($table in $tablesWithConstraints) {
    Write-Host " - Exporting constraints for table $table"
    # Call the new helper script for each table
    Export-DbObject "export_constraint.sql" $table (Join-Path $dirCons "$table`_CONSTRAINT.sql")
}

# export views
Write-Host "Exporting views..." -ForegroundColor Cyan
$views = Get-SqlResult "select view_name from user_views;"
foreach ($view in $views) {
    if ($view.Trim()) {
        Write-Host " - Exporting view $view"
        Export-DbObject "export_view.sql" $view (Join-Path $dirViews "$view.sql")
    }
}

# export remaining objects
Write-Host "Exporting remaining database objects..." -ForegroundColor Cyan
$otherObjectTypes = @(
    "TYPE",
    "SYNONYM",
    "DATABASE LINK",
    "PACKAGE",
    "PACKAGE BODY",
    "PROCEDURE",
    "FUNCTION",
    "OPERATOR",
    "MATERIALIZED VIEW",
    "MATERIALIZED VIEW LOG"
)
foreach ($objectType in $otherObjectTypes) {
    $objects = Get-SqlResult "select object_name from user_objects where object_type = '$objectType' and object_name not like 'BIN$%';"
    if ($objects) {
        Write-Host " - Exporting $objectType s:"
        foreach ($objectName in $objects) {
            Write-Host "   - $objectName"
            $outputFile = Join-Path $dirOther "$objectName.sql"
            # Use the new function to pass both the type and the name
            Export-GenericObject $objectType $objectName $outputFile
        }
    }
}



# ================================
# Combine Files for Each Category
# ================================
Write-Host "Combining individual files..." -ForegroundColor Cyan
$dirsToCombine = @{
    "01_seq" = $dirSeq;
    "02_tables"    = $dirTab;
    "03_trigs"     = $dirTrg;
    "04_data"      = $dirData;
    "05_cons"      = $dirCons;
    "06_views"     = $dirViews;
    "07_other"     = $dirOther
}
foreach ($item in $dirsToCombine.GetEnumerator()) {
    $dirPath = $item.Value 
    $combinedFileName = "$($item.Name.Substring(0, 2))_all_$($item.Name.Substring(3)).sql"
    $combinedFilePath = Join-Path $dirPath $combinedFileName
    $individualFilePaths = Get-ChildItem -Path $dirPath -Filter "*.sql" | Where-Object { $_.Name -notlike "all_*.sql" } | Select-Object -ExpandProperty FullName
    if ($individualFilePaths) {
        Write-Host " - Creating $combinedFilePath"
        $combinedContent = Get-Content -Path $individualFilePaths
        Set-Content -Path $combinedFilePath -Value $combinedContent
        Write-Host "   - Copying to combined folder..."
        Copy-Item -Path $combinedFilePath -Destination $dirCombined
    }
}


# ================================
# Generate Master Instruction File
# ================================
Write-Host "Generating master instruction file (README)..." -ForegroundColor Cyan
$rebuildScriptContent = @"
# =====================================================================
# MASTER REBUILD INSTRUCTIONS
# =====================================================================
# To restore the schema from this backup run the following files in order.
# =====================================================================

-- 1. Create schema objects
@01_seq\01_all_seq.sql
@02_tables\02_all_tables.sql
@03_trigs\03_all_trigs.sql
@05_cons\05_all_cons.sql
@06_views\06_all_views.sql
@07_other\07_all_other.sql

-- 2. Load data
@04_data\04_all_data.sql
"@
Set-Content -Path (Join-Path $baseDir "README_for_Master_Rebuild.txt") -Value $rebuildScriptContent

Write-Host ""
Write-Host "Backup complete! Files saved to $baseDir" -ForegroundColor Magenta
Write-Host ""
# ================================
