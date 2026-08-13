$ErrorActionPreference = 'Stop'

$texBin = 'C:\texlive\2022\bin\win32'
$sourceDir = [System.IO.Path]::GetFullPath(
    'D:\FpgaProject\XilinxProject\XC7A35T\fir_interpolation\submit\finally\images\source\cic_operator_flow'
)
$workDir = [System.IO.Path]::GetFullPath(
    'D:\FpgaProject\XilinxProject\XC7A35T\fir_interpolation\submit\finally\images\work\cic_operator_flow'
)
$outputDir = [System.IO.Path]::GetFullPath(
    'D:\FpgaProject\XilinxProject\XC7A35T\fir_interpolation\submit\finally\images\generated\cic_operator_flow'
)
$baseName = 'cic-operator-flow'
$source = Join-Path $sourceDir ($baseName + '.tex')
$workPdf = Join-Path $workDir ($baseName + '.pdf')

foreach ($directory in @($sourceDir, $workDir, $outputDir)) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw "Required directory is missing: $directory"
    }
}
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "TikZ source is missing: $source"
}

$env:Path = $texBin + ';' + $env:Path
& (Join-Path $texBin 'latexmk.exe') `
    '-xelatex' '-interaction=nonstopmode' '-halt-on-error' '-file-line-error' `
    ("-outdir=" + $workDir) $source
if ($LASTEXITCODE -ne 0) { throw 'XeLaTeX build failed.' }

Copy-Item -LiteralPath $workPdf `
    -Destination (Join-Path $outputDir ($baseName + '.pdf')) -Force

& (Join-Path $texBin 'dvisvgm.exe') `
    '--pdf' '--page=1' '--bbox=min' '--exact-bbox' '--no-fonts' '--precision=4' `
    ("--output=" + (Join-Path $outputDir ($baseName + '.svg'))) $workPdf
if ($LASTEXITCODE -ne 0) { throw 'SVG export failed.' }

& (Join-Path $texBin 'pdftocairo.exe') `
    '-png' '-singlefile' '-r' '600' $workPdf `
    (Join-Path $outputDir $baseName)
if ($LASTEXITCODE -ne 0) { throw 'PNG export failed.' }

Get-ChildItem -LiteralPath $outputDir -File |
    Where-Object { $_.BaseName -eq $baseName } |
    Sort-Object Extension |
    ForEach-Object {
        [pscustomobject]@{
            Name = $_.Name
            Bytes = $_.Length
            SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
