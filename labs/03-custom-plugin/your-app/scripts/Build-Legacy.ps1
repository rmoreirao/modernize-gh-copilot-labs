[CmdletBinding()]
param(
    [string]$AppRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$project = Join-Path $AppRoot 'src\OrderDesk.Legacy\OrderDesk.Legacy.csproj'
if (-not (Test-Path -LiteralPath $project)) { throw "Legacy project not found: $project" }
$pack = Join-Path ${env:ProgramFiles(x86)} 'Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8'
if (-not (Test-Path -LiteralPath $pack)) { throw 'Install the .NET Framework 4.8 Developer Pack before building.' }

$msbuildCommand = Get-Command MSBuild.exe -ErrorAction SilentlyContinue
if ($msbuildCommand) {
    $msbuild = $msbuildCommand.Source
} else {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Install Visual Studio Build Tools with MSBuild.' }
    $msbuild = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' |
        Select-Object -First 1
    if (-not $msbuild) { throw 'Visual Studio MSBuild was not found.' }
}

$packages = Join-Path $AppRoot 'packages'
& $msbuild $project /restore /p:RestorePackagesConfig=true "/p:RestoreRepositoryPath=$packages" /p:Configuration=Debug /nologo /verbosity:minimal
if ($LASTEXITCODE -ne 0) { throw "Legacy build failed with exit code $LASTEXITCODE." }
$executable = Join-Path $AppRoot 'src\OrderDesk.Legacy\bin\Debug\OrderDesk.Legacy.exe'
if (-not (Test-Path -LiteralPath $executable)) { throw "Build produced no executable: $executable" }
Write-Host "Legacy executable: $executable"
