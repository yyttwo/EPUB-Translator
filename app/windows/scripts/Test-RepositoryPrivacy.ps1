[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$allowedFixture = Join-Path $repoRoot 'fixtures\stage-1-self-authored.epub'
$generatedDirectoryPattern = '[\\/](?:\.git|\.vs|bin|obj|artifacts)[\\/]'
$forbiddenExtensions = @(
    '.pfx', '.p12', '.pem', '.key', '.cer', '.log', '.db', '.sqlite',
    '.exe', '.dll', '.pdb', '.msix', '.msixbundle', '.app', '.dmg'
)

$forbiddenFiles = Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Force |
    Where-Object {
        $_.FullName -notmatch $generatedDirectoryPattern -and
        (
            $forbiddenExtensions -contains $_.Extension.ToLowerInvariant() -or
            ($_.Extension -ieq '.epub' -and $_.FullName -ne $allowedFixture)
        )
    }

if ($forbiddenFiles) {
    throw "Forbidden private/binary artifacts found: $($forbiddenFiles.Name -join ', ')"
}

$textExtensions = @('.cs', '.csproj', '.props', '.sln', '.xaml', '.xml', '.md', '.ps1', '.json', '.pubxml', '.css', '.opf', '.svg')
$secretPattern = '(sk-[A-Za-z0-9_-]{16,}|Bearer\s+[A-Za-z0-9._~+/=-]{16,}|AIza[0-9A-Za-z_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----)'
$windowsUserRoot = '[A-Za-z]:\\' + 'Users\\'
$unixUserRoot = '/' + 'Users' + '/'
$privatePathPattern = "(${windowsUserRoot}[^\\\s]+|${unixUserRoot}[^/\s]+)"
$secretHits = @()
$privatePathHits = @()

Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Force |
    Where-Object {
        $_.FullName -notmatch $generatedDirectoryPattern -and
        $textExtensions -contains $_.Extension.ToLowerInvariant()
    } |
    ForEach-Object {
        $content = Get-Content -LiteralPath $_.FullName -Raw
        if ($content -match $secretPattern) {
            $secretHits += $_.FullName
        }

        if ($content -match $privatePathPattern) {
            $privatePathHits += $_.FullName
        }
    }

if ($secretHits) {
    throw "Possible real secret material found in: $($secretHits -join ', ')"
}

if ($privatePathHits) {
    throw "Private absolute path found: $($privatePathHits -join ', ')"
}

Write-Host 'Repository privacy scan PASS.'
