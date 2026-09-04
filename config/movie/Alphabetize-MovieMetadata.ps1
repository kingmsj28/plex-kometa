# Alphabetize-MovieMetadata.ps1
#
# Reads:  movie-metadata.yml
# Writes: movie-metadata-alphabetized.yml
#
# Rules:
# - Movie blocks begin with: "  12345: # Movie Title (2024)"
# - Sorts alphabetically by title
# - Ignores leading A / An / The when sorting
# - Ignores trailing year in parentheses when sorting
# - Preserves all nonblank content inside each movie block exactly
# - Removes blank lines inside movie blocks
# - Exactly ONE blank line between movies
# - NO blank line after "metadata:"
# - Original file is never modified
# - Output is UTF-8 without BOM
# - Verifies movie count, nonblank content, and URLs before saving

$ErrorActionPreference = "Stop"

$InputFile  = Join-Path $PSScriptRoot "movie-metadata.yml"
$OutputFile = Join-Path $PSScriptRoot "movie-metadata-alphabetized.yml"

if (-not (Test-Path $InputFile)) {
    Write-Host ""
    Write-Host "ERROR: Could not find:"
    Write-Host $InputFile
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "Reading movie metadata..."
Write-Host ""

$Lines = [System.IO.File]::ReadAllLines($InputFile)

# ------------------------------------------------------------
# Locate metadata:
# ------------------------------------------------------------

$MetadataIndex = -1

for ($i = 0; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i] -match '^metadata:\s*$') {
        $MetadataIndex = $i
        break
    }
}

if ($MetadataIndex -eq -1) {
    Write-Host "ERROR: Could not find top-level 'metadata:'"
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# ------------------------------------------------------------
# Parse movie blocks
# ------------------------------------------------------------

$Movies = @()
$CurrentMovie = $null

# Expected header:
#   12345: # Movie Title (2024)

$MovieHeaderRegex = '^  (\d+):\s+#\s*(.+?)\s*$'

for ($i = $MetadataIndex + 1; $i -lt $Lines.Count; $i++) {

    $Line = $Lines[$i]

    if ($Line -match $MovieHeaderRegex) {

        if ($null -ne $CurrentMovie) {
            $Movies += $CurrentMovie
        }

        $CurrentMovie = [PSCustomObject]@{
            ID     = $Matches[1]
            Comment = $Matches[2]
            Lines   = [System.Collections.Generic.List[string]]::new()
        }

        $CurrentMovie.Lines.Add($Line)
        continue
    }

    if ($null -ne $CurrentMovie) {

        # Remove all blank/whitespace-only lines from inside blocks.
        if (-not [string]::IsNullOrWhiteSpace($Line)) {
            $CurrentMovie.Lines.Add($Line)
        }
    }
}

if ($null -ne $CurrentMovie) {
    $Movies += $CurrentMovie
}

if ($Movies.Count -eq 0) {
    Write-Host "ERROR: No movie blocks were found."
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# ------------------------------------------------------------
# Check for duplicate TMDb IDs
# ------------------------------------------------------------

$DuplicateIDs = $Movies |
    Group-Object ID |
    Where-Object { $_.Count -gt 1 }

if ($DuplicateIDs) {

    Write-Host "ERROR: Duplicate movie IDs found:"
    Write-Host ""

    foreach ($Duplicate in $DuplicateIDs) {
        Write-Host "  $($Duplicate.Name) appears $($Duplicate.Count) times"
    }

    Write-Host ""
    Write-Host "No output file was written."
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# ------------------------------------------------------------
# Generate alphabetization key
# ------------------------------------------------------------

function Get-MovieSortKey {
    param(
        [string]$Comment
    )

    $Title = $Comment.Trim()

    # Remove trailing year:
    # Movie Title (2024)
    # becomes:
    # Movie Title

    $Title = $Title -replace '\s+\(\d{4}\)\s*$', ''

    # Ignore leading articles for alphabetization only.

    $Title = $Title -replace '^(?i:The|An|A)\s+', ''

    return $Title.Trim()
}

foreach ($Movie in $Movies) {
    $Movie | Add-Member `
        -NotePropertyName SortKey `
        -NotePropertyValue (Get-MovieSortKey $Movie.Comment)
}

$SortedMovies = $Movies |
    Sort-Object `
        @{ Expression = { $_.SortKey }; Ascending = $true },
        @{ Expression = { $_.Comment }; Ascending = $true },
        @{ Expression = { [long]$_.ID }; Ascending = $true }

# ------------------------------------------------------------
# Build output
# ------------------------------------------------------------

$OutputLines = [System.Collections.Generic.List[string]]::new()

$OutputLines.Add("metadata:")

for ($i = 0; $i -lt $SortedMovies.Count; $i++) {

    $Movie = $SortedMovies[$i]

    foreach ($Line in $Movie.Lines) {
        $OutputLines.Add($Line)
    }

    # Exactly one blank line BETWEEN movie blocks.
    if ($i -lt ($SortedMovies.Count - 1)) {
        $OutputLines.Add("")
    }
}

# ------------------------------------------------------------
# Safety checks
# ------------------------------------------------------------

$OriginalNonBlank = @(
    $Lines |
    Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    }
)

$NewNonBlank = @(
    $OutputLines |
    Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    }
)

# Count URLs

$OriginalURLs = @(
    foreach ($Line in $Lines) {
        if ($Line -match 'https?://\S+') {
            [regex]::Matches($Line, 'https?://\S+') |
                ForEach-Object { $_.Value }
        }
    }
)

$NewURLs = @(
    foreach ($Line in $OutputLines) {
        if ($Line -match 'https?://\S+') {
            [regex]::Matches($Line, 'https?://\S+') |
                ForEach-Object { $_.Value }
        }
    }
)

# Verify nonblank line count

if ($OriginalNonBlank.Count -ne $NewNonBlank.Count) {

    Write-Host "ERROR: Nonblank line count changed!"
    Write-Host ""
    Write-Host "Original: $($OriginalNonBlank.Count)"
    Write-Host "New:      $($NewNonBlank.Count)"
    Write-Host ""
    Write-Host "No output file was written."
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# Verify URL count

if ($OriginalURLs.Count -ne $NewURLs.Count) {

    Write-Host "ERROR: URL count changed!"
    Write-Host ""
    Write-Host "Original: $($OriginalURLs.Count)"
    Write-Host "New:      $($NewURLs.Count)"
    Write-Host ""
    Write-Host "No output file was written."
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# Verify exact nonblank content survived.
# Sorting is allowed, modification/deletion is not.

$OriginalContentCheck = $OriginalNonBlank | Sort-Object
$NewContentCheck      = $NewNonBlank      | Sort-Object

$Difference = Compare-Object `
    -ReferenceObject $OriginalContentCheck `
    -DifferenceObject $NewContentCheck

if ($Difference) {

    Write-Host "ERROR: Content changed during processing!"
    Write-Host ""
    Write-Host "No output file was written."
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# Verify exact URL set

$OriginalURLCheck = $OriginalURLs | Sort-Object
$NewURLCheck      = $NewURLs      | Sort-Object

$URLDifference = Compare-Object `
    -ReferenceObject $OriginalURLCheck `
    -DifferenceObject $NewURLCheck

if ($URLDifference) {

    Write-Host "ERROR: URLs changed during processing!"
    Write-Host ""
    Write-Host "No output file was written."
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# ------------------------------------------------------------
# Write UTF-8 WITHOUT BOM
# ------------------------------------------------------------

$UTF8NoBOM = New-Object System.Text.UTF8Encoding($false)

[System.IO.File]::WriteAllLines(
    $OutputFile,
    $OutputLines,
    $UTF8NoBOM
)

# ------------------------------------------------------------
# Results
# ------------------------------------------------------------

$OriginalBlankCount = $Lines.Count - $OriginalNonBlank.Count
$NewBlankCount      = $OutputLines.Count - $NewNonBlank.Count
$RemovedBlanks      = $OriginalBlankCount - $NewBlankCount

Write-Host "SUCCESS"
Write-Host ""
Write-Host "Movies:              $($Movies.Count)"
Write-Host "URLs:                $($OriginalURLs.Count)"
Write-Host "Nonblank lines:      $($OriginalNonBlank.Count)"
Write-Host "Original blank lines:$OriginalBlankCount"
Write-Host "New blank lines:     $NewBlankCount"
Write-Host "Blank lines removed: $RemovedBlanks"
Write-Host ""
Write-Host "Created:"
Write-Host $OutputFile
Write-Host ""
Write-Host "Original file was NOT modified."
Write-Host ""

Read-Host "Press Enter to exit"