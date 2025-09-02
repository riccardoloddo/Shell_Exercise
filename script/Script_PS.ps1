# Nome file di log con timestamp (per non sovrascrivere ogni volta)
$logFile = "C:\scp\log\script_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
function Write-Log {
    param(
        [string]$Message,
        [string]$Type = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy/MM/dd HH:mm:ss:fff"
    $scriptName = $MyInvocation.MyCommand.Name
    if (-not $scriptName) { $scriptName = "ConsoleHost" }

    $fullMessage = "[$timestamp - $scriptName - $Type] $Message"
    Add-Content -Path $logFile -Value $fullMessage
}

# Creo una funzione che esegue lo script .sql, cattura l'output e cerca eventuali errori ORA-XXXX
function Run-SQLPlus {
    param(
        [string]$Connection,
        [string]$SqlFile,
        [string[]]$SqlArgs
    )

    Write-Log "Eseguo SQL*Plus: $SqlFile" "INFO"
    $argsString = if ($SqlArgs) { $SqlArgs -join ' ' } else { "" }
    $cmd = "& sqlplus -S $Connection @$SqlFile $argsString"
    $output = Invoke-Expression $cmd
    Write-Log $output "INFO"

    if ($LASTEXITCODE -ne 0 -or $output -match "ORA-\d{5}") {
        Write-Log "Errore SQL*Plus rilevato in $SqlFile" "ERROR"
        throw "Errore SQL rilevato. Controlla il log."
    }

    Write-Log "SQL*Plus completato correttamente: $SqlFile" "INFO"
}

Write-Log "Script avviato." "INFO"
Write-Host ""
Write-Host "==============================" -ForegroundColor DarkGray
Write-Host "       SCRIPT AVVIATO         " -ForegroundColor Green
Write-Host "==============================" -ForegroundColor DarkGray
Write-Host ""

# Lettura dei parametri da $args con valori di default
$metodo    = if ($args.Count -ge 1) { $args[0] } else { "SQLLOADER" }
$path_dati = if ($args.Count -ge 2) { $args[1] } else { "C:\scp\data" }
$path_log  = if ($args.Count -ge 3) { $args[2] } else { "C:\scp\log" }

# Controllo metodo valido
$metodiValidi = @("SQLLOADER","EXTERNAL_TABLE","UTL_FILES")
if (-not ($metodiValidi -contains $metodo)) {
    $msg = "ERRORE: metodo '$metodo' non valido. Valori consentiti: SQLLOADER, EXTERNAL_TABLE, UTL_FILE."
    Write-Output $msg
    Write-Log "$msg -LogFile $path_log" "ERROR"
    Write-Host "" 
    Write-Host "!!! $msg -LogFile $path_log" -ForegroundColor Red
    exit 1
}

# Controllo file CSV
$fileCSV = Join-Path $path_dati "dati.csv"

if (-Not (Test-Path $fileCSV)) {
    Write-Log "Il file $fileCSV non esiste. Controllare il path dei dati." "ERROR"
    Write-Host ""
    Write-Host "ERRORE: Il file $fileCSV non esiste. Controllare il path dei dati." -ForegroundColor Red
    exit 1
}

if ((Get-Item $fileCSV).Length -eq 0) {
    Write-Log "Il file $fileCSV è vuoto." "ERROR"
    Write-Host ""
    Write-Host "ERRORE: Il file $fileCSV è vuoto." -ForegroundColor Red
    exit 1
}

Write-Log "Controllo CSV superato: trovato file $fileCSV non vuoto." "INFO"
Write-Host ""
Write-Host "[CHECK] Controllo CSV superato:" -ForegroundColor Cyan
Write-Host "   → Trovato file $fileCSV non vuoto." -ForegroundColor White
Write-Host ""

Write-Log "Input ricevuti: Metodo=$metodo, PathDati=$path_dati, PathLog=$path_log" "INFO"
Write-Host "[INPUT] Parametri ricevuti:" -ForegroundColor Cyan
Write-Host "   Metodo   = $metodo" -ForegroundColor White
Write-Host "   PathDati = $path_dati" -ForegroundColor White
Write-Host "   PathLog  = $path_log" -ForegroundColor White
Write-Host ""

# Legge connessioni
$lines = Get-Content "c:\scp\script\Configurazione\connection.config"
Write-Log "Connessioni caricate dal file di config." "INFO"

$connections = @{}
foreach ($line in $lines) {
    if ($line -match "^(.*?)=(.*)$") {
        $connections[$matches[1]] = $matches[2]
    }
}

# Esecuzione file generico con SYS
$sqlGenerico = "C:\scp\script\Environment\CREATE_ENV_DIN.sql"

# Esecuzione file metodo con SCPT
if ($metodo.ToUpper() -eq "EXTERNAL_TABLE") {
    Run-SQLPlus -Connection $connections['SYS'] -SqlFile $sqlGenerico -SqlArgs @($path_dati, $path_log)
    Write-Log "Eseguo l'istruzione: sqlplus -S $($connections['SYS']) @$sqlGenerico $path_dati $path_log." "INFO"
    Write-Log "Entro dentro il metodo EXTERNAL_TABLE." "INFO"
    $fileMetodo = "C:\scp\script\Tipi_caricamento\load_external_table.sql"
    Write-Host ">>> Eseguo metodo External Table..." -ForegroundColor Yellow
    Run-SQLPlus -Connection $connections['SCPT'] -SqlFile $fileMetodo
    Write-Log "Completato l'inserimento dei dati. Script terminato." "INFO"
}
elseif ($metodo.ToUpper() -eq "SQLLOADER") {
    Run-SQLPlus -Connection $connections['SYS'] -SqlFile $sqlGenerico -SqlArgs @($path_dati, $path_log)
    Write-Log "Entro dentro il metodo SQLLOADER." "INFO"
    $fileMetodo = "C:\scp\script\Tipi_caricamento\load_sqlloader.sql"
    $fileCTL    = "C:\scp\script\Tipi_caricamento\load_sqlloader.ctl"
    Write-Host ">>> Eseguo metodo SQL*Loader..." -ForegroundColor Yellow
    Run-SQLPlus -Connection $connections['SCPT'] -SqlFile $fileMetodo -SqlArgs @("PRELOAD")
    Invoke-Expression "& sqlldr $($connections['SCPT']) control=$fileCTL data=$path_dati\dati.csv log=$path_log\Log_scarti_00.log bad=C:\scp\bad\Bad_scarti_00.bad skip=1"
    Run-SQLPlus -Connection $connections['SCPT'] -SqlFile $fileMetodo -SqlArgs @("POSTLOAD")
    Write-Log "Completato l'inserimento dei dati. Script terminato." "INFO"
}
elseif ($metodo.ToUpper() -eq "UTL_FILES") {
    Run-SQLPlus -Connection $connections['SYS'] -SqlFile $sqlGenerico -SqlArgs @($path_dati, $path_log)
    Write-Log "Entro dentro il metodo UTL_FILES." "INFO"
    Write-Log "Eseguo l'istruzione: sqlplus -S $($connections['SYS']) @$sqlGenerico $path_dati $path_log." "INFO"
    $fileMetodo = "C:\scp\script\Tipi_caricamento\load_utl.sql"
    Write-Host ">>> Eseguo metodo UTL_FILES..." -ForegroundColor Yellow
    Run-SQLPlus -Connection $connections['SCPT'] -SqlFile $fileMetodo
    Write-Log "Completato l'inserimento dei dati. Script terminato." "INFO"
}
else {
    Write-Host ""
    Write-Host "!!! Nessun metodo trovato. Usare uno di questi tre: EXTERNAL_TABLE, SQLLOADER, UTL_FILES." -ForegroundColor Red
    Write-Log "Nessun metodo trovato." "ERROR"
    exit
}

Write-Host ""
Write-Host "==============================" -ForegroundColor DarkGray
Write-Host "     SCRIPT COMPLETATO        " -ForegroundColor Green
Write-Host "==============================" -ForegroundColor DarkGray
Write-Host ""


# REINIDIRZZARE GLI ERRORI. pENSARE ALLA errore 404 CHE MI RINDIRIZZA SU UN ALTRA PAGINA...
# Disabilitare l'auto-commit appena ci mettiamo a lavorare su una cosa....
# Pensare 1000 volte prima di droppare qualcosa..

#powershell SCHEDULAZIONE

#VEDERE LE PIPE LINE