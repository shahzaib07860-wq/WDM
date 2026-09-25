param([string]$InnoCompiler)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$bundle = Join-Path $root 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $bundle 'wdm.exe'))) { throw 'Build wdm.exe first: flutter build windows --release' }
$compiler = if ($InnoCompiler) { $InnoCompiler } else { Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe' }
if (-not (Test-Path $compiler)) { throw 'Inno Setup 6 is required.' }
$output = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$script = (Get-Content (Join-Path $root 'windows\packaging\exe\inno.iss') -Raw)
$script = $script.Replace('BASE_DIR', $root).Replace('OUTPUT_DIR', $output).Replace('SETUP_ICON_FILE', (Join-Path $root 'windows\runner\resources\app_icon.ico'))
$temp = Join-Path $output 'WDM-2-installer.iss'
Set-Content -Path $temp -Value $script -Encoding UTF8
& $compiler $temp
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
Write-Output (Join-Path $output 'WDM_2.0_Alpha_Setup.exe')
