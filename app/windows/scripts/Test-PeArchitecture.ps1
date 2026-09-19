[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [ValidateSet('x64', 'ARM64')]
    [string]$Expected
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$resolvedPath = (Resolve-Path -LiteralPath $Path).Path
$bytes = [IO.File]::ReadAllBytes($resolvedPath)
if ($bytes.Length -lt 64 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
    throw "Not a valid PE executable: $resolvedPath"
}

$peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
if ($peOffset -lt 0 -or $peOffset + 6 -gt $bytes.Length) {
    throw "Invalid PE header offset: $resolvedPath"
}

if ($bytes[$peOffset] -ne 0x50 -or $bytes[$peOffset + 1] -ne 0x45 -or
    $bytes[$peOffset + 2] -ne 0 -or $bytes[$peOffset + 3] -ne 0) {
    throw "PE signature is missing: $resolvedPath"
}

$machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
$expectedMachine = if ($Expected -eq 'x64') { 0x8664 } else { 0xAA64 }
if ($machine -ne $expectedMachine) {
    throw ('Expected {0} PE machine 0x{1:X4}; found 0x{2:X4}.' -f $Expected, $expectedMachine, $machine)
}

Write-Host "PE architecture PASS: $Expected"
