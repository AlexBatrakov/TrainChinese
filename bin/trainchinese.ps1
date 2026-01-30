# TrainChinese CLI wrapper for PowerShell
# Usage:
#   ./bin/trainchinese.ps1 --help

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Resolve-Path (Join-Path $scriptDir '..')

# Forward all args to the Julia entrypoint.
& julia --project="$rootDir" (Join-Path $rootDir 'train_chinese.jl') @args
exit $LASTEXITCODE
