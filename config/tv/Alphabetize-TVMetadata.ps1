# ============================================================
# TV Metadata Alphabetizer - SAFE VERSION
#
# What this script is allowed to change:
#   1. Order of complete show blocks
#   2. Blank-line spacing
#
# What it is NOT allowed to change:
#   - URLs
#   - Labels
#   - Posters
#   - Backgrounds
#   - Seasons
#   - Episodes
#   - Comments
#   - Indentation
#   - Any other nonblank line
#
# Output spacing:
#   - NO blank lines inside shows
#   - EXACTLY ONE blank line between shows
#
# The original file is NEVER overwritten.
# ============================================================


# ------------------------------------------------------------
# Find folder containing this script
# ------------------------------------------------------------

$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path


# ------------------------------------------------------------
# Find metadata YAML files
# ------------------------------------------------------------

$YamlFiles = @(
    Get-ChildItem -LiteralPath $ScriptFolder -File |
    Where-Object {
        $_.Extension -in ".yml", ".yaml" -and
        $_.BaseName -like "*metadata*" -and
        $_.BaseName -notlike "*-alphabetized"
    } |
    Sort-Object Name
)


if ($YamlFiles.Count -eq 0) {

    Write-Host ""
    Write-Host "No metadata YAML files found."
    Write-Host ""

    Read-Host "Press Enter to exit"
    exit
}


# ------------------------------------------------------------
# Selection menu
# ------------------------------------------------------------

Write-Host ""
Write-Host "========================================"
Write-Host " TV Metadata Alphabetizer"
Write-Host "========================================"
Write-Host ""
Write-Host "Choose a metadata YAML file:"
Write-Host ""


for ($i = 0; $i -lt $YamlFiles.Count; $i++) {

    Write-Host "  $($i + 1). $($YamlFiles[$i].Name)"
}


Write-Host ""

$SelectionNumber = 0


do {

    $Selection = Read-Host "Enter number"

    $ValidSelection =
        [int]::TryParse(
            $Selection,
            [ref]$SelectionNumber
        ) -and
        $SelectionNumber -ge 1 -and
        $SelectionNumber -le $YamlFiles.Count


    if (-not $ValidSelection) {

        Write-Host ""
        Write-Host "Invalid selection. Try again."
        Write-Host ""
    }

} until ($ValidSelection)


# ------------------------------------------------------------
# Selected file
# ------------------------------------------------------------

$InputFile = $YamlFiles[$SelectionNumber - 1]

$InputPath = $InputFile.FullName
$Directory = $InputFile.DirectoryName
$BaseName = $InputFile.BaseName
$Extension = $InputFile.Extension

$OutputPath = Join-Path `
    $Directory `
    "$BaseName-alphabetized$Extension"


Write-Host ""
Write-Host "Selected:"
Write-Host "  $($InputFile.Name)"
Write-Host ""


# ------------------------------------------------------------
# Read original
# ------------------------------------------------------------

$Lines = @(
    Get-Content -LiteralPath $InputPath
)

$OriginalLineCount = $Lines.Count

$OriginalNonBlankLines = @(
    $Lines |
    Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    }
)

$OriginalNonBlankCount = $OriginalNonBlankLines.Count


# ------------------------------------------------------------
# Find metadata:
# ------------------------------------------------------------

$MetadataIndex = -1


for ($i = 0; $i -lt $Lines.Count; $i++) {

    if ($Lines[$i].Trim() -eq "metadata:") {

        $MetadataIndex = $i
        break
    }
}


if ($MetadataIndex -eq -1) {

    Write-Host ""
    Write-Host "ERROR: Could not find 'metadata:'."
    Write-Host ""

    Read-Host "Press Enter to exit"
    exit
}


# ------------------------------------------------------------
# Preserve header
# ------------------------------------------------------------

$Header = @(
    $Lines[0..$MetadataIndex]
)


# ------------------------------------------------------------
# Find ONLY real show headers
#
# REQUIRED FORMAT:
#
#   73696: # CSI: NY (2004)
#
# Requirements:
#
# - EXACTLY two spaces
# - Numeric ID
# - Colon
# - # comment containing show title
#
# Season and episode keys cannot match this.
# ------------------------------------------------------------

$BlockStarts = @()


for ($i = $MetadataIndex + 1; $i -lt $Lines.Count; $i++) {

    if ($Lines[$i] -match '^  \d+:\s+#\s+.+$') {

        $BlockStarts += $i
    }
}


if ($BlockStarts.Count -eq 0) {

    Write-Host ""
    Write-Host "ERROR: No show headers were found."
    Write-Host ""
    Write-Host "Expected format:"
    Write-Host "  73696: # CSI: NY (2004)"
    Write-Host ""

    Read-Host "Press Enter to exit"
    exit
}


$OriginalShowCount = $BlockStarts.Count


Write-Host "Shows detected:"
Write-Host "  $OriginalShowCount"
Write-Host ""


# ------------------------------------------------------------
# Build complete show blocks
# ------------------------------------------------------------

$Blocks = @()


for ($b = 0; $b -lt $BlockStarts.Count; $b++) {

    $Start = $BlockStarts[$b]


    if ($b -lt ($BlockStarts.Count - 1)) {

        $End = $BlockStarts[$b + 1] - 1
    }
    else {

        $End = $Lines.Count - 1
    }


    $BlockLines = @(
        $Lines[$Start..$End]
    )


    # --------------------------------------------------------
    # Remove blank lines ONLY
    #
    # Every nonblank line is preserved exactly.
    # --------------------------------------------------------

    $CleanBlockLines = @(
        $BlockLines |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_)
        }
    )


    if ($CleanBlockLines.Count -eq 0) {

        Write-Host ""
        Write-Host "SAFETY ERROR:"
        Write-Host "An empty show block was detected."
        Write-Host ""
        Write-Host "Nothing was written."

        Read-Host "Press Enter to exit"
        exit
    }


    $FirstLine = $CleanBlockLines[0]


    # --------------------------------------------------------
    # Extract ID and title
    # --------------------------------------------------------

    if ($FirstLine -notmatch '^  (\d+):\s+#\s+(.+)$') {

        Write-Host ""
        Write-Host "SAFETY ERROR:"
        Write-Host "Could not understand this show header:"
        Write-Host ""
        Write-Host $FirstLine
        Write-Host ""
        Write-Host "Nothing was written."

        Read-Host "Press Enter to exit"
        exit
    }


    $Id = $Matches[1]
    $Title = $Matches[2]


    # --------------------------------------------------------
    # Create sorting title
    #
    # ONLY the temporary sorting value is modified.
    # The actual line remains untouched.
    # --------------------------------------------------------

    $SortTitle = $Title


    # Remove trailing year from SORT VALUE only

    $SortTitle =
        $SortTitle -replace '\s+\(\d{4}\)\s*$', ''


    # Ignore A / An / The from SORT VALUE only

    $SortTitle =
        $SortTitle -replace '^(?i)(A|An|The)\s+', ''


    $Blocks += [PSCustomObject]@{

        SortTitle = $SortTitle
        Title     = $Title
        Id        = [int64]$Id
        Lines     = $CleanBlockLines
    }
}


# ------------------------------------------------------------
# SAFETY CHECK #1
# Show count
# ------------------------------------------------------------

if ($Blocks.Count -ne $OriginalShowCount) {

    Write-Host ""
    Write-Host "========================================"
    Write-Host " SAFETY CHECK FAILED"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "Original shows: $OriginalShowCount"
    Write-Host "Processed shows: $($Blocks.Count)"
    Write-Host ""
    Write-Host "Nothing was written."

    Read-Host "Press Enter to exit"
    exit
}


# ------------------------------------------------------------
# Alphabetize
# ------------------------------------------------------------

$SortedBlocks = @(
    $Blocks |
    Sort-Object `
        @{Expression={$_.SortTitle}; Ascending=$true}, `
        @{Expression={$_.Title}; Ascending=$true}, `
        @{Expression={$_.Id}; Ascending=$true}
)


# ------------------------------------------------------------
# Build output
# ------------------------------------------------------------

$Output = New-Object `
    System.Collections.Generic.List[string]


# Header:
# preserve every nonblank header line exactly

foreach ($Line in $Header) {

    if (-not [string]::IsNullOrWhiteSpace($Line)) {

        $Output.Add($Line)
    }
}


# Shows

for ($i = 0; $i -lt $SortedBlocks.Count; $i++) {


    foreach ($Line in $SortedBlocks[$i].Lines) {

        $Output.Add($Line)
    }


    # EXACTLY one blank line between shows

    if ($i -lt ($SortedBlocks.Count - 1)) {

        $Output.Add("")
    }
}


# ------------------------------------------------------------
# SAFETY CHECK #2
#
# Number of nonblank lines MUST be identical.
# ------------------------------------------------------------

$OutputNonBlankLines = @(
    $Output |
    Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    }
)


if ($OutputNonBlankLines.Count -ne $OriginalNonBlankCount) {

    Write-Host ""
    Write-Host "========================================"
    Write-Host " SAFETY CHECK FAILED"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "Nonblank line count changed."
    Write-Host ""
    Write-Host "Original: $OriginalNonBlankCount"
    Write-Host "Output:   $($OutputNonBlankLines.Count)"
    Write-Host ""
    Write-Host "Nothing was written."

    Read-Host "Press Enter to exit"
    exit
}


# ------------------------------------------------------------
# SAFETY CHECK #3
#
# Verify every nonblank line exists the exact same
# number of times before and after.
#
# This catches:
#
# - changed URLs
# - deleted URLs
# - duplicated URLs
# - changed labels
# - changed episode numbers
# - changed indentation
# - changed comments
# - basically ANY content alteration
# ------------------------------------------------------------

$OriginalCounts = @{}
$OutputCounts = @{}


foreach ($Line in $OriginalNonBlankLines) {

    if ($OriginalCounts.ContainsKey($Line)) {

        $OriginalCounts[$Line]++
    }
    else {

        $OriginalCounts[$Line] = 1
    }
}


foreach ($Line in $OutputNonBlankLines) {

    if ($OutputCounts.ContainsKey($Line)) {

        $OutputCounts[$Line]++
    }
    else {

        $OutputCounts[$Line] = 1
    }
}


$ContentMismatch = $false


foreach ($Key in $OriginalCounts.Keys) {

    if (-not $OutputCounts.ContainsKey($Key)) {

        $ContentMismatch = $true
        break
    }


    if ($OriginalCounts[$Key] -ne $OutputCounts[$Key]) {

        $ContentMismatch = $true
        break
    }
}


if (-not $ContentMismatch) {

    foreach ($Key in $OutputCounts.Keys) {

        if (-not $OriginalCounts.ContainsKey($Key)) {

            $ContentMismatch = $true
            break
        }
    }
}


if ($ContentMismatch) {

    Write-Host ""
    Write-Host "========================================"
    Write-Host " SAFETY CHECK FAILED"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "Nonblank file content changed."
    Write-Host ""
    Write-Host "Nothing was written."

    Read-Host "Press Enter to exit"
    exit
}


# ------------------------------------------------------------
# SAFETY CHECK #4
#
# Explicit URL comparison
# ------------------------------------------------------------

$OriginalUrls = @(
    $OriginalNonBlankLines |
    ForEach-Object {

        if ($_ -match 'https?://\S+') {

            $Matches[0]
        }
    }
)


$OutputUrls = @(
    $OutputNonBlankLines |
    ForEach-Object {

        if ($_ -match 'https?://\S+') {

            $Matches[0]
        }
    }
)


$OriginalUrlCounts = @{}
$OutputUrlCounts = @{}


foreach ($Url in $OriginalUrls) {

    if ($OriginalUrlCounts.ContainsKey($Url)) {

        $OriginalUrlCounts[$Url]++
    }
    else {

        $OriginalUrlCounts[$Url] = 1
    }
}


foreach ($Url in $OutputUrls) {

    if ($OutputUrlCounts.ContainsKey($Url)) {

        $OutputUrlCounts[$Url]++
    }
    else {

        $OutputUrlCounts[$Url] = 1
    }
}


$UrlMismatch = $false


if ($OriginalUrls.Count -ne $OutputUrls.Count) {

    $UrlMismatch = $true
}


if (-not $UrlMismatch) {

    foreach ($Url in $OriginalUrlCounts.Keys) {

        if (-not $OutputUrlCounts.ContainsKey($Url)) {

            $UrlMismatch = $true
            break
        }


        if ($OriginalUrlCounts[$Url] -ne $OutputUrlCounts[$Url]) {

            $UrlMismatch = $true
            break
        }
    }
}


if ($UrlMismatch) {

    Write-Host ""
    Write-Host "========================================"
    Write-Host " URL SAFETY CHECK FAILED"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "Original URLs: $($OriginalUrls.Count)"
    Write-Host "Output URLs:   $($OutputUrls.Count)"
    Write-Host ""
    Write-Host "Nothing was written."

    Read-Host "Press Enter to exit"
    exit
}


# ------------------------------------------------------------
# Everything passed.
# Write file.
# ------------------------------------------------------------

$Utf8NoBom =
    New-Object System.Text.UTF8Encoding($false)


[System.IO.File]::WriteAllLines(
    $OutputPath,
    $Output,
    $Utf8NoBom
)


# ------------------------------------------------------------
# Results
# ------------------------------------------------------------

$NewLineCount = $Output.Count
$LinesRemoved = $OriginalLineCount - $NewLineCount


Write-Host ""
Write-Host "========================================"
Write-Host " DONE - ALL SAFETY CHECKS PASSED"
Write-Host "========================================"
Write-Host ""

Write-Host "Shows:"
Write-Host "  $OriginalShowCount"

Write-Host ""

Write-Host "URLs verified:"
Write-Host "  $($OriginalUrls.Count)"

Write-Host ""

Write-Host "Nonblank lines verified:"
Write-Host "  $OriginalNonBlankCount"

Write-Host ""

Write-Host "Original total lines:"
Write-Host "  $OriginalLineCount"

Write-Host ""

Write-Host "New total lines:"
Write-Host "  $NewLineCount"

Write-Host ""

if ($LinesRemoved -gt 0) {

    Write-Host "Blank lines removed:"
    Write-Host "  $LinesRemoved"
}
elseif ($LinesRemoved -eq 0) {

    Write-Host "Blank lines removed:"
    Write-Host "  0"
}
else {

    # This should be impossible with these spacing rules.
    Write-Host "WARNING:"
    Write-Host "Output unexpectedly contains more lines."
}


Write-Host ""
Write-Host "Created:"
Write-Host "  $([System.IO.Path]::GetFileName($OutputPath))"

Write-Host ""

Write-Host "Original file was NOT modified."
Write-Host ""

Read-Host "Press Enter to exit"