
# Tar emot sökvägen till konfigurationsfilen från Terraform
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath
)

Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop

# Läser inställningarna från config.json
try {
    $Config = Get-Content -LiteralPath $ConfigPath -Raw |
        ConvertFrom-Json

    # Hämtar källmapp och destinationsmapp
    [string]$SourcePath = $Config.source_path
    [string]$DestinationPath = $Config.destination_path

    # Hämtar filändelser som ska undantas
    [string[]]$ExcludedExtensions = @($Config.excluded_extensions)
}
catch {
    Write-Error "Kunde inte läsa konfigurationen: $_"
    exit 1
}

# Anger var loggfilen ska sparas
$script:LogFile = Join-Path $DestinationPath "backup.log"

# FUNKTION 1: Kontrollerar och skapar mappar
function Initialize-Environment {

    param(
        [string]$Source,
        [string]$Destination
    )

    try {
        # Skapar destinationsmappen om den saknas
        if (-not (Test-Path -LiteralPath $Destination)) {
            New-Item -ItemType Directory -Path $Destination -Force |
                Out-Null
        }

        # Kontrollerar att källmappen finns
        if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
            throw "Källmappen saknas: $Source"
        }

        Write-Log "Backupmiljön är redo."
    }
    catch {
        throw "Kunde inte konfigurera miljön: $_"
    }
}


# FUNKTION 2: Skriver information till loggfilen
function Write-Log {

    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    # Skapar en tidsstämpel
    $Date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Formaterar loggmeddelandet
    $Entry = "[$Date] [$Level] $Message"

    # Sparar meddelandet i backup.log
    Add-Content -LiteralPath $script:LogFile -Value $Entry

    # Visar meddelandet i PowerShell
    Write-Host $Entry
}


# FUNKTION 3: Genomför säkerhetskopieringen
function Invoke-Backup {

    param(
        [string]$Source,
        [string]$Destination,
        [string[]]$ExcludedExtensions
    )

    try {
        # Skapar en tidsstämpel för backupmappen
        $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

        # Skapar en unik mapp för säkerhetskopian
        $BackupPath = Join-Path $Destination "Backup_$Timestamp"

        New-Item -ItemType Directory -Path $BackupPath -Force |
            Out-Null

        Write-Log "Startar backup från $Source."

        # Hämtar alla filer som ska säkerhetskopieras
        $SourceFiles = @(
            Get-ChildItem -LiteralPath $Source -File -Recurse -Force |
            Where-Object {
                $_.Name -ne "desktop.ini" -and
                $ExcludedExtensions -notcontains $_.Extension
            }
        )

        # Räknar antalet filer
        [int]$FileCount = $SourceFiles.Count

        Write-Log "Hittade $FileCount filer."

        # Skapar argument till Robocopy
        $RobocopyArgs = @(
            $Source,
            $BackupPath,
            "/E",
            "/R:2",
            "/W:2",
            "/COPY:DAT",
            "/DCOPY:DAT"
        )

        # Lägger till filer och filändelser som ska undantas
        $RobocopyArgs += "/XF"
        $RobocopyArgs += "desktop.ini"

        if ($ExcludedExtensions.Count -gt 0) {
            foreach ($Extension in $ExcludedExtensions) {
                $RobocopyArgs += "*$Extension"
            }
        }

        # Kör Robocopy
        & robocopy @RobocopyArgs | Out-Null

        # Hämtar Robocopys resultatkod
        [int]$RobocopyResult = $LASTEXITCODE

        # Robocopy-koder under 8 innebär normalt godkänt resultat
        if ($RobocopyResult -ge 8) {
            throw "Robocopy misslyckades. Felkod: $RobocopyResult"
        }

        Write-Log "Backup genomförd. Robocopy-kod: $RobocopyResult" "SUCCESS"

        # Returnerar sökvägen till backupen
        return $BackupPath
    }
    catch {
        Write-Log "Backup misslyckades: $_" "ERROR"
        throw
    }
}


# FUNKTION 4: Kontrollerar att backupen fungerar
function Test-BackupHealth {

    param(
        [string]$Source,
        [string]$Backup,
        [string[]]$ExcludedExtensions
    )

    try {
        # Hämtar originalfilerna
        $SourceFiles = @(
            Get-ChildItem -LiteralPath $Source -File -Recurse -Force |
            Where-Object {
                $_.Name -ne "desktop.ini" -and
                $ExcludedExtensions -notcontains $_.Extension
            }
        )

        # Räknar verifierade filer
        [int]$VerifiedFiles = 0

        # Går igenom varje originalfil
        foreach ($File in $SourceFiles) {

            # Hämtar filens relativa sökväg
            $RelativePath = $File.FullName.Substring(
                $Source.TrimEnd('\', '/').Length
            ).TrimStart('\', '/')

            # Skapar sökvägen till motsvarande backupfil
            $BackupFile = Join-Path $Backup $RelativePath

            # Kontrollerar att backupfilen finns
            if (Test-Path -LiteralPath $BackupFile -PathType Leaf) {

                # Beräknar originalfilens SHA256
                $OriginalHash = (
                    Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256
                ).Hash

                # Beräknar backupfilens SHA256
                $BackupHash = (
                    Get-FileHash -LiteralPath $BackupFile -Algorithm SHA256
                ).Hash

                # Jämför filernas innehåll
                if ($OriginalHash -eq $BackupHash) {
                    $VerifiedFiles++
                }
                else {
                    throw "Filinnehållet stämmer inte: $RelativePath"
                }
            }
            else {
                throw "Backupfil saknas: $RelativePath"
            }
        }

        # Kontrollerar att alla filer verifierades
        if ($VerifiedFiles -eq $SourceFiles.Count) {

            Write-Log "HÄLSOKONTROLL GODKÄND: $VerifiedFiles filer verifierade." "SUCCESS"
        }
        else {
            throw "Alla filer kunde inte verifieras."
        }
    }
    catch {
        Write-Log "HÄLSOKONTROLL MISSLYCKAD: $_" "ERROR"
        throw
    }
}


# HUVUDFLÖDE: Kör hela backup-processen
try {

    # Kontrollerar att miljön är redo
    Initialize-Environment `
        -Source $SourcePath `
        -Destination $DestinationPath

    # Genomför säkerhetskopieringen
    $BackupResult = Invoke-Backup `
        -Source $SourcePath `
        -Destination $DestinationPath `
        -ExcludedExtensions $ExcludedExtensions

    # Verifierar backupen
    Test-BackupHealth `
        -Source $SourcePath `
        -Backup $BackupResult `
        -ExcludedExtensions $ExcludedExtensions

    # Skriver att hela processen lyckades
    Write-Log "Hela backup-processen är klar." "SUCCESS"

    exit 0
}
catch {

    # Loggar eventuella kritiska fel
    Write-Log "Kritiskt fel: $_" "ERROR"

    exit 1
}
