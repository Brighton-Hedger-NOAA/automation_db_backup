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
$dirSeq = Join-Path $baseDir "01_sequences"
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
    $sqlScript = @"
$sqlConnect
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 32767
$Query
EXIT
"@
    $result = ($sqlScript | & $sqlplusPath -S /nolog)
    return $result | Where-Object { $_ -and $_ -notlike '*SQL>*' -and $_ -notlike '*EXIT*' -and $_ -notlike '*exit*' -and $_ -notmatch '^\s*$' }
}
# function to run side scripts for main db objects (seq, tab, trig, data, view, cons)
# Function to call the export manager script
function Export-Object {
    param($Mode, $Arguments, $OutputFile)
    $sqlScript = @"
$sqlConnect
@export_objects.sql '$Mode' $Arguments
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
        Export-Object "SEQUENCE" "'$sequence'" (Join-Path $dirSeq "$sequence.sql")
    }
}

# export tab
Write-Host "Exporting table definitions..." -ForegroundColor Cyan
$tables = Get-SqlResult "select table_name from user_tables;"
foreach ($table in $tables) {
    if ($table.Trim()) {
        Write-Host " - Exporting table $table"
        Export-Object "TABLE" "'$table'" (Join-Path $dirTab "$table.sql")
    }
}

# export trig
Write-Host "Exporting triggers..." -ForegroundColor Cyan
$triggers = Get-SqlResult "select trigger_name from user_triggers;"
foreach ($trigger in $triggers) {
    if ($trigger.Trim()) {
        Write-Host " - Exporting trigger $trigger"
        Export-Object "TRIGGER" "'$trigger'" (Join-Path $dirTrg "$trigger.sql")
    }
}

# export data
Write-Host "Exporting data..." -ForegroundColor Cyan
$dataTables = Get-SqlResult "select table_name from user_tables where table_name not in ($excludeList) and table_name not like 'OCC_STR_DATA%' and table_name not like 'BIN$%';"
foreach ($table in $dataTables) {
    Write-Host " - Exporting data for $table"
    $outputFile = Join-Path $dirData "$($table)_DATA_TABLE.sql"
    Export-Object "DATA" "'$table'" (Join-Path $dirData "$($table)_data.sql")
}

# export OCC_STR_DATA tables as .csv's
Write-Host "Exporting large string data tables..." -ForegroundColor Cyan
$strTables = Get-SqlResult "select table_name from user_tables where table_name like 'OCC_STR_DATA%';"
foreach ($table in $strTables) {
    if ($table.Trim()) {
        Write-Host " - Generating SQL*Loader files for $table"
        $ctlContent = @"
LOAD DATA
INFILE *
INTO TABLE $table
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
(all columns need to be listed manually)
"@
        Set-Content -Path (Join-Path $dirStr "$table.ctl") -Value $ctlContent
        $csvScript = @"
$sqlConnect
set colsep ',' head off pagesize 0 feedback off trimspool on linesize 32767;
spool "$(Join-Path $dirStr "$table.csv")"
select * from $table;
spool off;
exit;
"@
        $csvScript | & $sqlplusPath -S /nolog | Out-Null
    }
}

# export cons
Write-Host "Exporting constraints..." -ForegroundColor Cyan
$tablesWithConstraints = Get-SqlResult "SELECT DISTINCT uc.table_name FROM user_constraints uc JOIN user_tables ut ON uc.table_name = ut.table_name WHERE uc.constraint_name NOT LIKE 'BIN$%';"

foreach ($table in $tablesWithConstraints) {
    Write-Host " - Exporting constraints for table $table"
    Export-Object "TABLE_CONSTRAINTS" "'$table'" (Join-Path $dirCons "$($table)_constraints.sql")
}

# export views
Write-Host "Exporting views..." -ForegroundColor Cyan
$views = Get-SqlResult "select view_name from user_views;"
foreach ($view in $views) {
    if ($view.Trim()) {
        Write-Host " - Exporting view $view"
        Export-Object "VIEW" "'$view'" (Join-Path $dirViews "$view.sql")
    }
}

# export remaining objects
Write-Host "Exporting 'Other' objects..." -ForegroundColor Green
$otherObjectTypes = @("TYPE", "SYNONYM", "DATABASE LINK", "PACKAGE", "PACKAGE BODY", "PROCEDURE", "FUNCTION", "OPERATOR", "MATERIALIZED VIEW", "MATERIALIZED VIEW LOG")
foreach ($objectType in $otherObjectTypes) {
    $objects = Get-SqlResult "select object_name from user_objects where object_type = '$objectType' and object_name not like 'BIN$%';"
    if ($objects) {
        Write-Host " - Exporting objects of type: $objectType"
        foreach ($objectName in $objects) {
            Write-Host "   - $objectName"
            Export-Object "GENERIC" "'$objectType' '$objectName'" (Join-Path $dirOther "$objectName.sql")
        }
    }
}


# ================================
# Combine Files for Each Category
# ================================
Write-Host "Combining individual files..." -ForegroundColor Cyan

$dirsToCombine = @{
    "01_sequences" = $dirSeq;
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
        
        # CORRECTED: Read all content into a variable first to avoid file locking
        $combinedContent = Get-Content -Path $individualFilePaths
        
        # Now, write the content from the variable to the new file
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
@01_sequences\01_all_sequences.sql
@02_tables\02_all_tables.sql
@06_views\06_all_views.sql

-- 2. Load data
@04_data\04_all_data.sql

-- 3. Apply constraints and create other objects
@05_cons\05_all_cons.sql
@03_trigs\03_all_trigs.sql
@07_other\07_all_other.sql
"@
Set-Content -Path (Join-Path $baseDir "README_for_Master_Rebuild.txt") -Value $rebuildScriptContent

Write-Host ""
Write-Host "Backup complete!" -ForegroundColor Magenta
Write-Host ""
# ================================
