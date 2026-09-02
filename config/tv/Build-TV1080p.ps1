$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$InputFiles = @(
    (Join-Path $ScriptDir "tv-metadata.yml"),
    (Join-Path $ScriptDir "food-metadata.yml")
)

$OutputFile = Join-Path $ScriptDir "tv-1080p.yml"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

function Get-IndentCount {
    param([string]$Line)

    if ($Line -match '^(\s*)') {
        return $Matches[1].Length
    }

    return 0
}

function Strip-TitleCardsAndEpisodes {
    param(
        [string[]]$Lines
    )

    $Result = New-Object System.Collections.Generic.List[string]

    $SkippingEpisodes = $false
    $EpisodesIndent = -1

    foreach ($Line in $Lines) {

        $Indent = Get-IndentCount $Line

        # ----------------------------------------------------
        # Currently inside an episodes: section
        # ----------------------------------------------------

        if ($SkippingEpisodes) {

            # Blank lines inside episode data are discarded.
            if ([string]::IsNullOrWhiteSpace($Line)) {
                continue
            }

            # Stay inside episode section while indentation
            # remains deeper than the episodes: line.
            if ($Indent -gt $EpisodesIndent) {
                continue
            }

            # We've reached the next season/property.
            $SkippingEpisodes = $false
            $EpisodesIndent = -1
        }

        # ----------------------------------------------------
        # Start of episodes: section
        # ----------------------------------------------------

        if ($Line -match '^\s+episodes:\s*$') {
            $SkippingEpisodes = $true
            $EpisodesIndent = $Indent
            continue
        }

        # ----------------------------------------------------
        # Remove only the Title Cards* label
        # ----------------------------------------------------

        if ($Line -match '^\s*-\s*Title Cards\*\s*$') {
            continue
        }

        $Result.Add($Line)
    }

    return $Result.ToArray()
}

function Get-ShowBlocks {
    param(
        [string[]]$Lines,
        [string]$SourceName
    )

    $Blocks = New-Object System.Collections.Generic.List[object]

    $CurrentBlock = $null
    $CurrentID = $null
    $CurrentTitle = $null

    foreach ($Line in $Lines) {

        # Standard show header:
        #   70327: # Buffy the Vampire Slayer (1997)

        if ($Line -match '^  (\d+):\s+#\s*(.+?)\s*$') {

            if ($null -ne $CurrentBlock) {
                $Blocks.Add([PSCustomObject]@{
                    ID         = $CurrentID
                    Title      = $CurrentTitle
                    Source     = $SourceName
                    Lines      = $CurrentBlock.ToArray()
                })
            }

            $CurrentID = $Matches[1]
            $CurrentTitle = $Matches[2]

            $CurrentBlock = New-Object System.Collections.Generic.List[string]
            $CurrentBlock.Add($Line)

            continue
        }

        if ($null -ne $CurrentBlock) {
            $CurrentBlock.Add($Line)
        }
    }

    if ($null -ne $CurrentBlock) {
        $Blocks.Add([PSCustomObject]@{
            ID         = $CurrentID
            Title      = $CurrentTitle
            Source     = $SourceName
            Lines      = $CurrentBlock.ToArray()
        })
    }

    return $Blocks.ToArray()
}

# ------------------------------------------------------------
# Verify source files
# ------------------------------------------------------------

foreach ($File in $InputFiles) {
    if (-not (Test-Path -LiteralPath $File)) {
        throw "Missing input file: $File"
    }
}

# ------------------------------------------------------------
# Read both metadata files
# ------------------------------------------------------------

$AllBlocks = New-Object System.Collections.Generic.List[object]

foreach ($File in $InputFiles) {

    Write-Host ""
    Write-Host "Reading: $(Split-Path $File -Leaf)"

    $Lines = [System.IO.File]::ReadAllLines($File)

    $Blocks = Get-ShowBlocks `
        -Lines $Lines `
        -SourceName (Split-Path $File -Leaf)

    Write-Host "  Shows found: $($Blocks.Count)"

    foreach ($Block in $Blocks) {
        $AllBlocks.Add($Block)
    }
}

# ------------------------------------------------------------
# Safety check for duplicate TVDB IDs
# ------------------------------------------------------------

$Duplicates = $AllBlocks |
    Group-Object ID |
    Where-Object { $_.Count -gt 1 }

if ($Duplicates) {

    Write-Host ""
    Write-Host "ERROR: Duplicate TVDB IDs were found:" -ForegroundColor Red

    foreach ($Duplicate in $Duplicates) {

        Write-Host ""
        Write-Host "TVDB ID: $($Duplicate.Name)" -ForegroundColor Yellow

        foreach ($Item in $Duplicate.Group) {
            Write-Host "  $($Item.Title) [$($Item.Source)]"
        }
    }

    throw "Duplicate shows detected. tv-1080p.yml was NOT created."
}

# ------------------------------------------------------------
# Build stripped blocks
# ------------------------------------------------------------

$OutputBlocks = New-Object System.Collections.Generic.List[object]

foreach ($Block in $AllBlocks) {

    $CleanLines = Strip-TitleCardsAndEpisodes -Lines $Block.Lines

    # Remove blank lines from beginning/end of each block.
    while (
        $CleanLines.Count -gt 0 -and
        [string]::IsNullOrWhiteSpace($CleanLines[0])
    ) {
        $CleanLines = $CleanLines[1..($CleanLines.Count - 1)]
    }

    while (
        $CleanLines.Count -gt 0 -and
        [string]::IsNullOrWhiteSpace($CleanLines[-1])
    ) {
        if ($CleanLines.Count -eq 1) {
            $CleanLines = @()
        }
        else {
            $CleanLines = $CleanLines[0..($CleanLines.Count - 2)]
        }
    }

    $OutputBlocks.Add([PSCustomObject]@{
        ID    = $Block.ID
        Title = $Block.Title
        Lines = $CleanLines
    })
}

# ------------------------------------------------------------
# Alphabetize shows
#
# Ignores A / An / The when sorting, while preserving the
# actual show header exactly as it appeared.
# ------------------------------------------------------------

$OutputBlocks = $OutputBlocks | Sort-Object {

    $SortTitle = $_.Title

    # Remove trailing year for sorting.
    $SortTitle = $SortTitle -replace '\s+\(\d{4}\)\s*$', ''

    # Ignore leading articles.
    $SortTitle = $SortTitle -replace '^(?i)(A|An|The)\s+', ''

    $SortTitle
}

# ------------------------------------------------------------
# Build output
# ------------------------------------------------------------

$OutputLines = New-Object System.Collections.Generic.List[string]

$OutputLines.Add("metadata:")
$OutputLines.Add("")

foreach ($Block in $OutputBlocks) {

    foreach ($Line in $Block.Lines) {
        $OutputLines.Add($Line)
    }

    $OutputLines.Add("")
}

# Remove final blank line.
if (
    $OutputLines.Count -gt 0 -and
    [string]::IsNullOrWhiteSpace($OutputLines[-1])
) {
    $OutputLines.RemoveAt($OutputLines.Count - 1)
}

# ------------------------------------------------------------
# Final safety checks
# ------------------------------------------------------------

$OutputText = $OutputLines -join "`r`n"

if ($OutputText -match '(?m)^\s+episodes:\s*$') {
    throw "Safety check failed: an episodes: section remains."
}

if ($OutputText -match '(?m)^\s*-\s*Title Cards\*\s*$') {
    throw "Safety check failed: a Title Cards* label remains."
}

$OutputShowCount = (
    $OutputLines |
    Where-Object { $_ -match '^  \d+:\s+#\s+.+' }
).Count

if ($OutputShowCount -ne $AllBlocks.Count) {
    throw "Safety check failed: show count changed."
}

# ------------------------------------------------------------
# Write UTF-8 without BOM
# ------------------------------------------------------------

$UTF8NoBOM = New-Object System.Text.UTF8Encoding($false)

[System.IO.File]::WriteAllText(
    $OutputFile,
    $OutputText + "`r`n",
    $UTF8NoBOM
)

# ------------------------------------------------------------
# Done
# ------------------------------------------------------------

Write-Host ""
Write-Host "============================================"
Write-Host " TV 1080p metadata successfully generated"
Write-Host "============================================"
Write-Host ""
Write-Host "Input files:"
Write-Host "  tv-metadata.yml"
Write-Host "  food-metadata.yml"
Write-Host ""
Write-Host "Shows: $($AllBlocks.Count)"
Write-Host "Episodes/title cards: REMOVED"
Write-Host "Title Cards* labels:  REMOVED"
Write-Host ""
Write-Host "Created:"
Write-Host "  $OutputFile"
Write-Host ""
Write-Host "Press Enter to close..."
[void][System.Console]::ReadLine()