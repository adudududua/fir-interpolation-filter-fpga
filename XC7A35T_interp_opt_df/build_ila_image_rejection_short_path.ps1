#=============================================================
# 文件名       : build_ila_image_rejection_short_path.ps1
# 脚本名       : build_ila_image_rejection_short_path
# 功能简述     : 使用临时短盘符运行 ILA 镜像抑制版完整构建，规避
#                Vivado 2018.3 调试核临时文件路径过长的问题。
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-19
# 版本         : V2018.3
# 开发工具     : Vivado / PowerShell
# 修订记录     :
#                2026-07-19：新增短路径完整构建入口。
#=============================================================

param(
    [switch]$ImplementationOnly
)

$ErrorActionPreference = 'Stop'

$vivadoBat = 'E:\app\Xilinx2018.3\Vivado\2018.3\bin\vivado.bat'
$projectDirectory = (Resolve-Path $PSScriptRoot).Path
$temporaryDrive = 'Q:'
$temporaryRoot = "$temporaryDrive\"
$driveWasCreated = $false

if (-not (Test-Path -LiteralPath $vivadoBat)) {
    throw "Vivado 2018.3 not found: $vivadoBat"
}

if (Test-Path -LiteralPath $temporaryRoot) {
    throw "Temporary drive $temporaryDrive is already in use. Remove that mapping or change temporaryDrive in this script."
}

try {
    & subst $temporaryDrive $projectDirectory
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to map $temporaryDrive to $projectDirectory"
    }
    $driveWasCreated = $true

    $arguments = @(
        '-mode', 'batch',
        '-source', "$temporaryDrive\build_ila_image_rejection.tcl"
    )
    if ($ImplementationOnly) {
        $arguments += @('-tclargs', 'impl_only')
    }

    & $vivadoBat @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado build failed with exit code $LASTEXITCODE"
    }
}
finally {
    if ($driveWasCreated) {
        & subst $temporaryDrive /D
    }
}

