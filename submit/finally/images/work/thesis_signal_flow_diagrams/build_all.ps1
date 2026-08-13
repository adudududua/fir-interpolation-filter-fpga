param([int]$PngDpi = 600)
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\..')).Path
$source = Join-Path $workspace 'submit\finally\images\source\thesis_signal_flow_diagrams'
$output = Join-Path $workspace 'submit\finally\images\generated\thesis_signal_flow_diagrams'
$build = Join-Path $PSScriptRoot 'build'
$texbin = 'C:\texlive\2022\bin\win32'
$names = @(
  '01_cic_algorithm_signal_flow',
  '02_cic_rtl_signal_flow',
  '03_stage1_polyphase_signal_flow',
  '04_stage23_shared_mac_signal_flow'
)
New-Item -ItemType Directory -Force -Path $output,$build | Out-Null
Push-Location $source
try {
  foreach($name in $names){
    & "$texbin\latexmk.exe" -xelatex -interaction=nonstopmode -halt-on-error -file-line-error "-outdir=$build" "$name.tex"
    if($LASTEXITCODE -ne 0){ throw "XeLaTeX failed: $name" }
    Copy-Item -LiteralPath (Join-Path $build "$name.pdf") -Destination (Join-Path $output "$name.pdf") -Force
    & "$texbin\dvisvgm.exe" --pdf --page=1 --bbox=min --exact-bbox --no-fonts --precision=4 "--output=$(Join-Path $output "$name.svg")" (Join-Path $output "$name.pdf")
    if($LASTEXITCODE -ne 0){ throw "SVG export failed: $name" }
    & "$texbin\pdftocairo.exe" -png -singlefile -r $PngDpi (Join-Path $output "$name.pdf") (Join-Path $output $name)
    if($LASTEXITCODE -ne 0){ throw "PNG export failed: $name" }
  }
  & "$texbin\pdfunite.exe" @($names | ForEach-Object { Join-Path $output "$_.pdf" }) (Join-Path $output 'thesis_signal_flow_diagram_set.pdf')
  if($LASTEXITCODE -ne 0){ throw 'PDF merge failed' }

  $artifactNames = @()
  foreach($name in $names){
    $artifactNames += "$name.pdf"
    $artifactNames += "$name.svg"
    $artifactNames += "$name.png"
  }
  $artifactNames += 'thesis_signal_flow_diagram_set.pdf'
  $manifest = foreach($artifactName in $artifactNames){
    $artifactPath = Join-Path $output $artifactName
    $item = Get-Item -LiteralPath $artifactPath
    [pscustomobject]@{
      file = $artifactName
      bytes = $item.Length
      sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $artifactPath).Hash.ToLowerInvariant()
    }
  }
  $manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $output 'build_manifest.json') -Encoding UTF8
}
finally { Pop-Location }
Write-Output "Built $($names.Count) signal-flow figures in $output"
