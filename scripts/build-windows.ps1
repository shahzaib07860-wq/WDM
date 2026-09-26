$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This build requires Windows 10/11 x64.' }
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $root
$logDir = Join-Path $root 'build-logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir ('build-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
$exitCode = 0
Start-Transcript -Path $log | Out-Null
function Invoke-Checked {
    param([string]$Command, [string[]]$Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Command failed (exit $LASTEXITCODE): $Command $($Arguments -join ' ')" }
}
try {
    $missing = @()
    foreach ($name in @('flutter', 'dart', 'git')) {
        if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { $missing += "$name must be installed and available on PATH." }
    }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vs = if (Test-Path $vswhere) {
        & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    }
    if (-not $vs) { $missing += 'Install Visual Studio with Desktop development with C++, including the Windows SDK and CMake tools.' }
    $isccCommand = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    $compilerCandidates = @(
        $(if ($isccCommand) { $isccCommand.Source }),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
    )
    $compiler = $compilerCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $compiler) { $missing += 'Install Inno Setup 6 (ISCC.exe).' }
    if ($missing.Count -gt 0) { throw ("Build prerequisites are missing:`n- " + ($missing -join "`n- ")) }

    Invoke-Checked 'flutter' @('doctor', '-v')
    Invoke-Checked 'flutter' @('pub', 'get')
    Invoke-Checked 'flutter' @('analyze', '--no-fatal-infos', '--no-fatal-warnings')
    Invoke-Checked 'flutter' @('test', 'test/legacy_tools_test.dart', 'test/runtime_settings_test.dart')
    Invoke-Checked 'dart' @('run', 'tests/queue-policy-test.dart')
    Invoke-Checked 'node' @('test-extension.cjs')
    Invoke-Checked 'flutter' @('build', 'windows', '--release')
    & (Join-Path $PSScriptRoot 'build-windows-installer.ps1') -InnoCompiler $compiler
    $installer = Join-Path $root 'dist\WDM_2.0_Alpha_Setup.exe'
    if (-not (Test-Path $installer)) { throw 'The installer was not produced.' }
    Get-FileHash -Algorithm SHA256 $installer | Format-List
    Write-Host "BUILD SUCCEEDED: $installer"
    Write-Host 'Run the Windows acceptance checks in BUILD-WINDOWS.md before distributing this alpha.'
} catch {
    $exitCode = 1
    Write-Host "BUILD FAILED: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    Stop-Transcript | Out-Null
    Write-Host "Build log: $log"
}
exit $exitCode
