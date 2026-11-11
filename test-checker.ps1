
# TestBackup.ps1
# Kontrollerar att backupsystemet fungerar korrekt

param(
    [string]$ConfigPath = "C:\teobackups\config.json"
)

# Räknar godkända tester
[int]$PassedTests = 0

# Räknar misslyckade tester
[int]$FailedTests = 0


# Funktion som visar testresultat
function Write-TestResult {

    param(
        [string]$TestName,
        [bool]$Success
    )

    if ($Success) {
        Write-Host "[GODKÄND] $TestName" -ForegroundColor Green
        $script:PassedTests++
    }
    else {
        Write-Host "[MISSLYCKAD] $TestName" -ForegroundColor Red
        $script:FailedTests++
    }
}


# TEST 2: Kontrollerar att config.json finns
Write-TestResult `
    -TestName "Config.json finns" `
    -Success (Test-Path -LiteralPath $ConfigPath -PathType Leaf)


# Stoppar testet om konfigurationsfilen saknas
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    Write-Host "Testet kan inte fortsätta utan config.json." -ForegroundColor Red
    exit 1
}


# Läser konfigurationen
try {
    $Config = Get-Content -LiteralPath $ConfigPath -Raw |
        ConvertFrom-Json

    $SourcePath = $Config.source_path
    $BackupFolder = $Config.destination_path
    $LogFile = Join-Path $BackupFolder "backup.log"
    $ExcludedExtensions = @($Config.excluded_extensions)
}
catch {
    Write-Host "Kunde inte läsa konfigurationen: $_" -ForegroundColor Red
    exit 1
}

# TEST 1: Kontrollerar att backupmappen finns
Write-TestResult `
    -TestName "Backupmappen finns" `
    -Success (Test-Path -LiteralPath $BackupFolder -PathType Container)


# TEST 3: Kontrollerar att källmappen finns
Write-TestResult `
    -TestName "Källmappen finns" `
    -Success (Test-Path -LiteralPath $SourcePath -PathType Container)


# Hämtar den senaste backupmappen
$LatestBackup = Get-ChildItem -LiteralPath $BackupFolder -Directory |
    Where-Object { $_.Name -like "Backup_*" } |
    Sort-Object Name -Descending |
    Select-Object -First 1


# TEST 4: Kontrollerar att en backup har skapats
$BackupExists = $null -ne $LatestBackup

Write-TestResult `
    -TestName "Backup har skapats" `
    -Success $BackupExists


# TEST 5: Kontrollerar att loggfilen finns
Write-TestResult `
    -TestName "Loggfilen finns" `
    -Success (Test-Path -LiteralPath $LogFile -PathType Leaf)


# Fortsätter endast om en backup finns
if ($BackupExists -and (Test-Path -LiteralPath $SourcePath -PathType Container)) {

    # Hämtar alla originalfiler som inte är undantagna
    $SourceFiles = @(
        Get-ChildItem -LiteralPath $SourcePath -File -Recurse -Force |
        Where-Object {
            $_.Name -ne "desktop.ini" -and
            $ExcludedExtensions -notcontains $_.Extension
        }
    )

    # Räknar verifierade filer
    [int]$VerifiedFiles = 0

    # Kontrollerar varje fil
    foreach ($File in $SourceFiles) {

        # Hämtar filens relativa sökväg
        $RelativePath = $File.FullName.Substring(
            $SourcePath.TrimEnd('\', '/').Length
        ).TrimStart('\', '/')

        # Hittar motsvarande backupfil
        $BackupFile = Join-Path $LatestBackup.FullName $RelativePath

        if (Test-Path -LiteralPath $BackupFile -PathType Leaf) {

            # Jämför originalfilens och backupfilens SHA256
            $OriginalHash = (
                Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256
            ).Hash

            $BackupHash = (
                Get-FileHash -LiteralPath $BackupFile -Algorithm SHA256
            ).Hash

            if ($OriginalHash -eq $BackupHash) {
                $VerifiedFiles++
            }
        }
    }

    # TEST 6: Kontrollerar att alla filer är identiska
    $AllFilesVerified = $VerifiedFiles -eq $SourceFiles.Count

    Write-TestResult `
        -TestName "Alla backupfiler är verifierade med SHA256" `
        -Success $AllFilesVerified

    Write-Host "Verifierade filer: $VerifiedFiles av $($SourceFiles.Count)"
}
else {
    Write-TestResult `
        -TestName "Alla backupfiler är verifierade med SHA256" `
        -Success $false
}


# Visar sammanfattning av testerna
Write-Host ""
Write-Host "========== TESTRESULTAT =========="

Write-Host "Godkända tester: $PassedTests" -ForegroundColor Green
Write-Host "Misslyckade tester: $FailedTests" -ForegroundColor Red

# Kontrollerar om samtliga tester lyckades
if ($FailedTests -eq 0) {
    Write-Host "BACKUPSYSTEMET FUNGERAR!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "BACKUPSYSTEMET HAR FEL!" -ForegroundColor Red
    exit 1
}
