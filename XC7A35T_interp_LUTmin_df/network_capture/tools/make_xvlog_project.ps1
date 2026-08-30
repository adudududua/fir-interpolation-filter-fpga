$ErrorActionPreference = 'Stop'
$project = [xml](Get-Content -LiteralPath 'XC7A35T_interp.xpr' -Raw)
$sourceRoot = (Resolve-Path -LiteralPath 'XC7A35T_interp.srcs').Path
$projectRoot = (Resolve-Path -LiteralPath '.').Path
$out = Join-Path $projectRoot 'network_capture\results\full_top.prj'
$workLibrary = if ($env:DAC24_XSIM_LIBRARY) {
    $env:DAC24_XSIM_LIBRARY
} else { 'work' }
$includeDirs = @(
    (Join-Path $sourceRoot 'sources_1\new\all2x_v2'),
    (Join-Path $sourceRoot 'sources_1\new\all2x_v3'),
    (Join-Path $sourceRoot 'sources_1\new\all2x_v4'),
    (Join-Path $sourceRoot 'sources_1\new\all2x_v5'),
    (Join-Path $sourceRoot 'sources_1\new\all2x_v6'),
    (Join-Path $sourceRoot 'sources_1\new\all2x_v7')
)
$includeFlags = ($includeDirs | ForEach-Object {
    '--include "{0}"' -f $_.Replace('\', '/')
}) -join ' '
$lines = @()
$nodes = ($project.Project.FileSets.FileSet | Where-Object Name -eq 'sources_1').File
foreach ($node in $nodes) {
    $path = [string]$node.Path
    if ($path.StartsWith('$PSRCDIR/')) {
        $full = Join-Path $sourceRoot $path.Substring(9)
    } elseif ($path.StartsWith('$PPRDIR/')) {
        $full = Join-Path $projectRoot $path.Substring(8)
    } else {
        continue
    }
    if ($full -match '\.(v|sv)$' -and (Test-Path -LiteralPath $full)) {
        $lines += ('sv {0} {1} "{2}"' -f $workLibrary, $includeFlags,
                   $full.Replace('\', '/'))
    }
}
Set-Content -LiteralPath $out -Value $lines -Encoding ascii
Write-Output $out
