param([string]$OutputDirectory = 'build\windows-x64', [switch]$SkipTests)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = $PSScriptRoot
$output = [IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
New-Item -ItemType Directory -Force $output | Out-Null
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (!(Test-Path $vswhere)) { throw 'Install Visual Studio 2022 C++ Build Tools with Windows 11 SDK and Clang.' }
$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$installation) { throw 'C++ Build Tools were not found.' }
# Use the x64 host tools as well on Windows ARM's x64 emulation.
$nativeArchitecture = $env:PROCESSOR_ARCHITECTURE
$hostArchitecture = 'x64'
$developerCommand = '""{0}\Common7\Tools\VsDevCmd.bat" -no_logo -arch=x64 -host_arch={1} >nul && set"' -f $installation, $hostArchitecture
& cmd.exe /d /s /c $developerCommand | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process') }
}
if ($LASTEXITCODE -ne 0) { throw 'Cannot initialize x64 build environment.' }
$compilerCandidates = @("$installation\VC\Tools\Llvm\x64\bin\clang-cl.exe", "$installation\VC\Tools\Llvm\bin\clang-cl.exe") | Where-Object { Test-Path $_ }
if ($nativeArchitecture -eq 'ARM64' -and (Test-Path "$installation\VC\Tools\Llvm\ARM64\bin\clang-cl.exe")) {
    $compilerCandidates = @("$installation\VC\Tools\Llvm\ARM64\bin\clang-cl.exe") + $compilerCandidates
}
$clang = $compilerCandidates | Select-Object -First 1
if (!$clang) { throw 'Install the Visual Studio C++ Clang compiler component.' }
function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}
Push-Location $root
try {
    $common = @('--target=x86_64-pc-windows-msvc', '/nologo', '/O2', '/MT', '/DUNICODE', '/D_UNICODE', '/DNOMINMAX', '/D_USE_MATH_DEFINES', '/D_WIN32_WINNT=0x0A00')
    Invoke-Checked $clang ($common + @('/std:c11', '/W4', '-Wno-unused-function', '/c', 'Source\Windows\core.c', "/Fo$output\core.obj"))
    $sources = @('Source\Windows\app.cpp', 'Source\Windows\settings.cpp', 'Source\Windows\capture.cpp', 'Source\Windows\serial.cpp', 'Source\Windows\runtime.cpp', 'Tests\test_windows.cpp')
    $objects = @("$output\core.obj")
    foreach ($source in $sources) {
        $object = Join-Path $output (([IO.Path]::GetFileNameWithoutExtension($source)) + '.obj')
        Invoke-Checked $clang ($common + @('/std:c++20', '/EHsc', '/W4', '/c', $source, "/Fo$object"))
        $objects += $object
    }
    Invoke-Checked 'rc.exe' @('/nologo', "/fo$output\app.res", 'Source\Windows\app.rc')
    Invoke-Checked $clang ($common + $objects + @("$output\app.res", "/Fe$output\Glowline.exe", '/link', '/SUBSYSTEM:WINDOWS', '/MACHINE:X64', '/DYNAMICBASE', '/NXCOMPAT', '/HIGHENTROPYVA', 'windowsapp.lib', 'd3d11.lib', 'dxgi.lib', 'd3dcompiler.lib', 'comctl32.lib', 'comdlg32.lib', 'shell32.lib', 'ole32.lib', 'advapi32.lib', 'user32.lib', 'gdi32.lib', 'dwmapi.lib', 'wtsapi32.lib', 'uxtheme.lib', 'gdiplus.lib'))
    if (!$SkipTests) {
        $report = Join-Path $output 'contracts.txt'
        $process = Start-Process (Join-Path $output 'Glowline.exe') -ArgumentList @('--self-test', "`"$report`"") -Wait -PassThru
        if (Test-Path $report) { Get-Content $report }
        if ($process.ExitCode -ne 0) { throw "Windows contracts failed: $($process.ExitCode)" }
    }
    Write-Host "Built Windows 11 x64: $output\Glowline.exe"
} finally { Pop-Location }
