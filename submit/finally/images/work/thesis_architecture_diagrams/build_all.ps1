param(
    [int]$PngDpi = 600
)

$ErrorActionPreference = 'Stop'

$repoRoot = 'D:\FpgaProject\XilinxProject\XC7A35T\fir_interpolation'
$sourceDir = Join-Path $repoRoot 'submit\finally\images\source\thesis_architecture_diagrams'
$workDir = Join-Path $repoRoot 'submit\finally\images\work\thesis_architecture_diagrams\build'
$outputDir = Join-Path $repoRoot 'submit\finally\images\generated\thesis_architecture_diagrams'
$texBin = 'C:\texlive\2022\bin\win32'

$latexmk = Join-Path $texBin 'latexmk.exe'
$dvisvgm = Join-Path $texBin 'dvisvgm.exe'
$pdftocairo = Join-Path $texBin 'pdftocairo.exe'
$pdfunite = Join-Path $texBin 'pdfunite.exe'

foreach ($tool in @($latexmk, $dvisvgm, $pdftocairo)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Required tool not found: $tool"
    }
}

New-Item -ItemType Directory -Force -Path $workDir, $outputDir | Out-Null

$figures = @(
    'board_system_architecture',
    'fir_cic_multirate_chain',
    'shared_resource_microarchitecture',
    'resource_allocation_2dsp',
    'verification_evidence_chain',
    'test_matrix_results'
)

Push-Location $sourceDir
try {
    foreach ($name in $figures) {
        $texPath = Join-Path $sourceDir ($name + '.tex')
        if (-not (Test-Path -LiteralPath $texPath -PathType Leaf)) {
            throw "Source not found: $texPath"
        }

        $outDirArgument = "-outdir=$workDir"
        & $latexmk -xelatex -interaction=nonstopmode -halt-on-error -file-line-error `
            $outDirArgument $texPath
        if ($LASTEXITCODE -ne 0) {
            throw "XeLaTeX failed for $name"
        }

        $builtPdf = Join-Path $workDir ($name + '.pdf')
        $outPdf = Join-Path $outputDir ($name + '.pdf')
        $outSvg = Join-Path $outputDir ($name + '.svg')
        $pngStem = Join-Path $outputDir $name

        Copy-Item -LiteralPath $builtPdf -Destination $outPdf -Force

        & $dvisvgm --pdf --page=1 --bbox=min --exact-bbox --no-fonts --precision=4 `
            --output=$outSvg $outPdf
        if ($LASTEXITCODE -ne 0) {
            throw "SVG export failed for $name"
        }

        & $pdftocairo -png -singlefile -r $PngDpi $outPdf $pngStem
        if ($LASTEXITCODE -ne 0) {
            throw "PNG export failed for $name"
        }
    }

    if (Test-Path -LiteralPath $pdfunite -PathType Leaf) {
        $pdfInputs = @($figures | ForEach-Object { Join-Path $outputDir ($_.ToString() + '.pdf') })
        $setPdf = Join-Path $outputDir 'thesis_architecture_diagram_set.pdf'
        & $pdfunite @pdfInputs $setPdf
        if ($LASTEXITCODE -ne 0) {
            throw 'PDF set assembly failed'
        }
    }
}
finally {
    Pop-Location
}

$manifest = foreach ($name in $figures) {
    foreach ($ext in @('pdf', 'svg', 'png')) {
        $file = Join-Path $outputDir ($name + '.' + $ext)
        $item = Get-Item -LiteralPath $file
        $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $file
        [pscustomobject]@{
            figure = $name
            format = $ext
            bytes = $item.Length
            sha256 = $hash.Hash.ToLowerInvariant()
        }
    }
}

$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath `
    (Join-Path $outputDir 'build_manifest.json') -Encoding UTF8

Write-Host "Built $($figures.Count) figures in $outputDir"
