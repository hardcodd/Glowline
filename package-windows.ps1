param([string]$BuildDirectory = 'build\windows-x64', [string]$OutputDirectory = 'Releases')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = $PSScriptRoot
$build = [IO.Path]::GetFullPath((Join-Path $root $BuildDirectory))
$output = [IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
$exe = Join-Path $build 'Glowline.exe'
# Check the PE machine field; an ARM64 development host must still produce x64.
$reader = [IO.BinaryReader]::new([IO.File]::OpenRead($exe))
try {
    if ($reader.ReadUInt16() -ne 0x5a4d) { throw 'Missing DOS executable header.' }
    $reader.BaseStream.Position = 0x3c
    $offset = $reader.ReadUInt32()
    $reader.BaseStream.Position = $offset
    if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) { throw 'The executable is not Windows x64.' }
} finally { $reader.Dispose() }
$version = (Get-Content (Join-Path $root 'VERSION.json') -Raw | ConvertFrom-Json).version
New-Item -ItemType Directory -Force $output | Out-Null
$zip = Join-Path $output "Glowline-$version-Windows-11-x64.zip"
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('Glowline package ' + [guid]::NewGuid())
try {
    $stage = Join-Path $temporary 'Glowline'
    New-Item -ItemType Directory -Force $stage | Out-Null
    Copy-Item $exe $stage
    Copy-Item (Join-Path $root 'LICENSE') $stage
    foreach ($language in @('en', 'ru')) {
        $source = if ($language -eq 'en') { 'WINDOWS.md' } else { 'WINDOWS.ru.md' }
        $text = [IO.File]::ReadAllText((Join-Path $root "docs\$source"))
        $text = $text.Replace('(WINDOWS.ru.md)', '(README.ru.md)').Replace('(WINDOWS.md)', '(README.en.md)')
        $text = $text.Replace('(../README.en.md)', '(https://github.com/hardcodd/Glowline/blob/main/README.en.md)')
        $text = $text.Replace('(../README.md)', '(https://github.com/hardcodd/Glowline)')
        [IO.File]::WriteAllText((Join-Path $stage "README.$language.md"), $text)
    }
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    # Explicit forward slashes also make Windows-built ZIPs portable to other extractors.
    $zipStream = [IO.File]::Open($zip, [IO.FileMode]::Create)
    try {
        $archive = [IO.Compression.ZipArchive]::new($zipStream, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($file in Get-ChildItem $stage -File) {
                [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName,
                    "Glowline/$($file.Name)", [IO.Compression.CompressionLevel]::Optimal) | Out-Null
            }
        } finally { $archive.Dispose() }
    } finally { $zipStream.Dispose() }
    $expanded = Join-Path $temporary 'round trip'
    Expand-Archive -Path $zip -DestinationPath $expanded
    $restored = Join-Path $expanded 'Glowline\Glowline.exe'
    if ((Get-FileHash $restored).Hash -ne (Get-FileHash $exe).Hash) { throw 'ZIP executable hash mismatch.' }
    $report = Join-Path $temporary 'contracts.txt'
    $process = Start-Process $restored -ArgumentList @('--self-test', "`"$report`"") -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw 'Extracted executable contracts failed.' }
    Get-Content $report
    $hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText("$zip.sha256", "$hash  $([IO.Path]::GetFileName($zip))`n")
    Write-Host "Verified Windows 11 x64 ZIP: $zip"
} finally { if (Test-Path $temporary) { Remove-Item $temporary -Recurse -Force } }
