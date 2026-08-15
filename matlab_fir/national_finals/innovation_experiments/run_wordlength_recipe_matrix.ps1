[CmdletBinding()]
param(
    [string]$Vivado = 'E:\app\Xilinx20252\2025.2\Vivado\bin\vivado.bat',
    [string]$OutputRoot = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$vivadoRoot = Split-Path -Parent (Split-Path -Parent $Vivado)
$tclStore = Join-Path $vivadoRoot 'data\XilinxTclStore'
if (Test-Path -LiteralPath $tclStore) {
    $env:XILINX_TCLAPP_REPO = $tclStore
    $env:TCLLIBPATH = (@(
        (Join-Path $tclStore 'support\appinit'),
        (Join-Path $tclStore 'support'),
        (Join-Path $tclStore 'tclapp')
    ) | ForEach-Object { $_.Replace('\', '/') }) -join ' '
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot 'matlab_fir\national_finals\_work\innovation_validation_20260815\experiment3\implementation_recipes'
}
$projectResults = Join-Path $repoRoot 'XC7A35T_interp_opt_2025.2\tools\vivado_2025_2\results'
$tcl = Join-Path $PSScriptRoot 'reroute_checkpoint_recipe.tcl'
$variants = @(
    @{ Name = '24_22_20'; Dcp = Join-Path $projectResults '20260810_181833\board_synthesized_2025_2.dcp' },
    @{ Name = '24_20_20'; Dcp = Join-Path $projectResults '20260811_183609\board_synthesized_2025_2.dcp' }
)
$recipes = @('explore', 'default', 'extra_timing')

foreach ($variant in $variants) {
    if (-not (Test-Path -LiteralPath $variant.Dcp)) {
        throw "Missing synthesized DCP: $($variant.Dcp)"
    }
    foreach ($recipe in $recipes) {
        $out = Join-Path $OutputRoot "$($variant.Name)_$recipe"
        New-Item -ItemType Directory -Path $out -Force | Out-Null
        if (Test-Path -LiteralPath (Join-Path $out 'recipe_summary.txt')) {
            Write-Host "Skipping completed recipe: $($variant.Name)/$recipe"
            continue
        }
        Push-Location $out
        try {
            & $Vivado -mode batch -source $tcl -tclargs $variant.Dcp $out $recipe 1
            if ($LASTEXITCODE -ne 0) {
                throw "Vivado failed for $($variant.Name)/$recipe"
            }
        }
        finally {
            Pop-Location
        }
    }
}
Write-Host "WORDLENGTH_RECIPE_MATRIX_PASS=$OutputRoot"
