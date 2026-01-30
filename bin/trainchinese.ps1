# TrainChinese CLI wrapper for PowerShell
# Usage:
#   ./bin/trainchinese.ps1 --help

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Resolve-Path (Join-Path $scriptDir '..')

$cliDir = Join-Path $rootDir 'cli'

if (!(Test-Path (Join-Path $cliDir 'Project.toml'))) {
	Write-Error "TrainChinese: missing $cliDir\Project.toml"
	exit 2
}

# First run: install dependencies for the CLI environment.
if (!(Test-Path (Join-Path $cliDir 'Manifest.toml'))) {
	Write-Host 'TrainChinese: installing CLI dependencies (first run)...'
	& julia --project="$cliDir" -e 'import Pkg; Pkg.instantiate()'
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

# Forward all args to the Julia entrypoint.
& julia --project="$cliDir" (Join-Path $rootDir 'train_chinese.jl') @args
exit $LASTEXITCODE
