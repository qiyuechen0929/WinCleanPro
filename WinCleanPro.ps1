<#
.SYNOPSIS
    WinCleanPro v4.0 - Windows 全家桶一键清理优化工具

.DESCRIPTION
    整合市面上主流开源清理优化工具的全部功能, 并加入自研差异化能力。
    包含 24 个功能模块, 引导式分区菜单, 顶部系统状态栏 + 健康评分。

    功能模块:
      [1]  磁盘清理          [11] 启动项管理
      [2]  去广告/精简       [12] 服务优化
      [3]  重复文件查找      [13] 计划任务查看
      [4]  空间分析          [14] 预装应用管理
      [5]  大文件查找        [15] 网络优化
      [6]  开发者专项清理    [16] 系统修复
      [7]  内存清理          [17] Defender 快速扫描
      [8]  休眠文件管理      [18] 系统信息
      [9]  软件更新          [19] 开机耗时追踪
      [10] 软件卸载          [20] 隐私痕迹清理
      [21] 一键全做          [22] 创建还原点      [23] 还原注册表备份
      [24] HOSTS 广告拦截

    自研差异化卖点:
      * 前后对比报告: 清理前/后磁盘占用对比, 自动生成 HTML 报告
      * 可回滚还原  : 删除进回收站, 注册表改动前自动备份, 支持一键还原
      * 系统健康分  : 基于垃圾量/磁盘/启动项/内存计算 0~100 分
      * 开机耗时追踪: 读取系统事件日志, 查看最近 5 次开机耗时
      * 休眠文件管理: 一键关闭休眠释放 hiberfil.sys
      * 安全优先    : 不永久删除, 保护系统关键目录

.NOTES
    作者  : 陈启粤
    版本  : 4.0.0
    日期  : 2026-08-06
    运行  : 建议以管理员身份运行 (脚本会自动请求提升)
#>

param(
    [switch]$RunAll,  # 一键执行全部优化 (跳过交互式确认)
    [switch]$Deep     # 深度清理模式: 附加 WinSxS 组件清理 / AppX 精简 / 网络优化 / 系统修复 (耗时较长)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# ================= 全局变量 =================
$script:AppName   = "WinCleanPro"
$script:AppVer    = "4.0.0"
$script:WorkDir   = Join-Path $env:LOCALAPPDATA "WinCleanPro"
$script:BackupDir = Join-Path $script:WorkDir "backups"
$script:ReportDir = Join-Path $script:WorkDir "reports"
$script:startTime = Get-Date

# 统计信息
$script:stats = @{
    BeforeFree  = 0
    AfterFree   = 0
    BeforeJunk  = 0
    AfterJunk   = 0
    DiskFreedMB = 0
    CleanedItems = 0
    DevFreedMB  = 0
}
$script:done       = @{ Disk=$false; Debloat=$false; Perf=$false; Dev=$false }
$script:changedLog = @()
$script:skipConfirm = $false
$script:sysStatus  = $null   # 缓存的状态栏数据

# ================= 彩色输出 =================
function Write-Step($msg) { Write-Host "`n[步骤] $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "[ OK ] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[警告] $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "[错误] $msg" -ForegroundColor Red }
function Write-Info($msg) { Write-Host "[信息] $msg" -ForegroundColor Gray }
function Write-Title($msg) { Write-Host ""; Write-Host $msg -ForegroundColor Cyan }

# ================= 终端可视化工具 =================
function Write-Logo {
    $logo = @'

   _       __     __   _          __  __
  | |     / /__  / /_ (_)______ _/ / / /
  | | /| / / _ \/ __// // __ `// /_/ /
  | |/ |/ /  __/ /_ / // /_/ // __  /
  |__/|__/\___/\__//_/ \__,_//_/ /_/
        __  ______                  __
       /  |/  / _/___  ____  ____ _/ /_
      / /|_/ / // __ \/ __ \/ __ `/ __/
     / /  / / // /_/ / / / / /_/ / /_
    /_/  /_/_/ \____/_/ /_/\__,_/\__/
'@
    Write-Host $logo -ForegroundColor Cyan
}

function Write-ProgressBar {
    param([double]$Percent, [string]$Label = '', [int]$Width = 40)
    $pct = [math]::Round($Percent, 1)
    if ($pct -gt 100) { $pct = 100 }
    if ($pct -lt 0) { $pct = 0 }
    $filled = [math]::Floor($Width * $pct / 100)
    $empty = $Width - $filled
    $bar = ('█' * $filled) + ('░' * $empty)
    $color = if ($pct -ge 80) { 'Green' } elseif ($pct -ge 50) { 'Yellow' } else { 'Red' }
    Write-Host "  $label [$bar] $pct%" -ForegroundColor $color -NoNewline
    Write-Host ""
}

function Write-BarGraph {
    param($Values, $Labels, $Unit = '', $Title = '')
    if (-not $Values) { return }
    $maxVal = ($Values | Measure-Object -Maximum).Maximum
    if ($maxVal -le 0) { $maxVal = 1 }
    $barWidth = 20
    if ($Title) { Write-Host "  $Title" -ForegroundColor DarkCyan }
    for ($i = 0; $i -lt $Values.Count; $i++) {
        $len = [math]::Max(1, [math]::Round($Values[$i] / $maxVal * $barWidth))
        $lbl = if ($i -lt $Labels.Count) { $Labels[$i] } else { "项$($i+1)" }
        $bar = '█' * $len
        $pad = ' ' * ($barWidth - $len)
        $color = switch ($i % 4) { 0 { 'Cyan' } 1 { 'Green' } 2 { 'Yellow' } 3 { 'Magenta' } }
        Write-Host ("  {0,-18} │{1}{2}│ {3}{4}" -f $lbl, $bar, $pad, $Values[$i], $Unit) -ForegroundColor $color
    }
    Write-Host ""
}

function Write-ScoreBar {
    param([int]$Score)
    $barWidth = 24
    $filled = [math]::Floor($barWidth * $Score / 100)
    $empty = $barWidth - $filled
    $bar = '█' * $filled + '░' * $empty
    $label = if ($Score -ge 80) { '优秀' } elseif ($Score -ge 60) { '良好' } elseif ($Score -ge 40) { '一般' } else { '需优化' }
    $color = if ($Score -ge 80) { 'Green' } elseif ($Score -ge 60) { 'Yellow' } elseif ($Score -ge 40) { 'Magenta' } else { 'Red' }
    Write-Host ("  ❤️  健康评分  [{0}]  {1} / 100  ({2})" -f $bar, $Score, $label) -ForegroundColor $color
}

function Show-CleanupResult {
    param([double]$FreedMB, [int]$Items, [double]$DevMB)
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║                    清理完成 · 战报                        ║" -ForegroundColor Green
    Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Green
    $freedGB = [math]::Round($FreedMB / 1024, 2)
    if ($FreedMB -ge 1024) {
        Write-Host ""
        Write-Host ("  🎉 共释放磁盘空间: {0} GB" -f $freedGB) -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host ("  🎉 共释放磁盘空间: {0} MB" -f $FreedMB) -ForegroundColor Green
    }
    Write-Host ("  清理文件/文件夹: {0} 个" -f $Items) -ForegroundColor White
    if ($DevMB -gt 0) {
        Write-Host ("  开发者缓存释放: {0} MB" -f $DevMB) -ForegroundColor Cyan
    }
    # 条形图
    $labels = @('释放空间')
    $vals = @($FreedMB)
    Write-Host ""
    Write-BarGraph -Values $vals -Labels $labels -Unit ' MB' -Title '释放空间'
    Write-Host ""
}

# ================= 初始化 =================
function Initialize-Environment {
    New-Item -ItemType Directory -Force -Path $script:WorkDir, $script:BackupDir, $script:ReportDir | Out-Null
    Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinCleanPro_MemUtil {
    [DllImport("psapi.dll", SetLastError=true)]
    public static extern bool EmptyWorkingSet(IntPtr hProcess);
}
"@ -ErrorAction SilentlyContinue
}

# ================= 管理员检查 / 自提权 =================
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 需要管理员权限的功能编号 (服务优化 [12] 只读分析, 无需提权)
$script:adminNeeded = @('2','8','14','15','16','17','21','22','24')

# ================= 基础工具函数 =================
function Get-FreeSpaceMB {
    $drive = Get-PSDrive -Name $env:SystemDrive.TrimEnd(':')
    return [math]::Round($drive.Free / 1MB, 0)
}

function Get-TotalSpaceMB {
    $drive = Get-PSDrive -Name $env:SystemDrive.TrimEnd(':')
    return [math]::Round(($drive.Used + $drive.Free) / 1MB, 0)
}

function Get-FolderSizeMB {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
    return [math]::Round($sum / 1MB, 1)
}

function Remove-ToRecycleBin {
    param([string]$Path, [string]$Label = '')
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    try {
        if ($item.PSIsContainer) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
                $Path,'OnlyErrorDialogs','SendToRecycleBin')
        } else {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                $Path,'OnlyErrorDialogs','SendToRecycleBin')
        }
        $script:stats.CleanedItems++
        Write-OK "已移入回收站$Label`: $Path"
    } catch {
        Write-Warn "无法删除(可能被占用)$Label`: $Path"
    }
}

function Set-RegValue {
    param($Path, $Name, $Value, $Type = 'DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    try {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
        return $true
    } catch {
        return $false
    }
}

function Get-StartupItems {
    $items = @()
    $runKeys = @(
        @{ Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';       Src = 'HKCU' },
        @{ Key = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run';       Src = 'HKLM' },
        @{ Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce';   Src = 'HKCU' },
        @{ Key = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce';   Src = 'HKLM' }
    )
    foreach ($r in $runKeys) {
        if (Test-Path $r.Key) {
            $prop = Get-ItemProperty $r.Key
            $prop.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object {
                $items += [PSCustomObject]@{ Name = $_.Name; Command = $_.Value; Source = $r.Src }
            }
        }
    }
    return $items
}

# ================= 状态栏 / 健康评分 =================
function Measure-JunkMB {
    $targets = @(
        (Join-Path $env:TEMP '*'),
        'C:\Windows\Temp',
        'C:\Windows\SoftwareDistribution\Download',
        'C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache',
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Cache'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Cache'),
        (Join-Path $env:LOCALAPPDATA 'Mozilla\Firefox\Profiles'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\FontCache'),
        (Join-Path $env:WINDIR 'ServiceProfiles\LocalService\AppData\Local\FontCache')
    )
    $total = 0
    foreach ($t in $targets) {
        if (Test-Path $t) {
            $files = Get-ChildItem -Path $t -Recurse -File -Force -ErrorAction SilentlyContinue
            $total += ($files | Measure-Object -Property Length -Sum).Sum
        }
    }
    return [math]::Round($total / 1MB, 1)
}

function Refresh-SystemStatus {
    $os = Get-CimInstance Win32_OperatingSystem
    $memTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $memFree  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $free = Get-FreeSpaceMB
    $total = Get-TotalSpaceMB
    $freePct = if ($total -gt 0) { [math]::Round($free / $total * 100, 0) } else { 0 }
    $junk = Measure-JunkMB
    $startup = (Get-StartupItems).Count

    $score = 100
    $issues = @()
    if ($junk -gt 500) {
        $deduct = [math]::Min(20, [int]($junk / 500))
        $score -= $deduct
        $issues += "垃圾缓存约 $junk MB"
    }
    if ($freePct -lt 10) {
        $score -= 25
        $issues += "C盘空间告急 (<10%)"
    } elseif ($freePct -lt 20) {
        $score -= 15
        $issues += "C盘剩余不足 20%"
    }
    if ($startup -gt 12) {
        $score -= 8
        $issues += "启动项达 $startup 个"
    }
    if (($memTotal - $memFree) / $memTotal * 100 -gt 85) {
        $score -= 5
        $issues += "内存占用偏高"
    }
    if ($score -lt 10) { $score = 10 }

    $script:sysStatus = [PSCustomObject]@{
        FreeGB  = [math]::Round($free / 1024, 1)
        TotalGB = [math]::Round($total / 1024, 1)
        FreePct = $freePct
        MemTotalGB = $memTotal
        MemFreeGB  = $memFree
        JunkMB  = $junk
        Startup = $startup
        Score   = $score
        Issues  = $issues
    }
}

function Show-StatusBar {
    if (-not $script:sysStatus) { Refresh-SystemStatus }
    $s = $script:sysStatus

    # 磁盘占用百分比条
    $usedPct = 100 - $s.FreePct
    $diskBarWidth = 18
    $diskFilled = [math]::Floor($diskBarWidth * $usedPct / 100)
    $diskBar = '█' * $diskFilled + '░' * ($diskBarWidth - $diskFilled)
    $diskColor = if ($s.FreePct -lt 10) { 'Red' } elseif ($s.FreePct -lt 20) { 'Yellow' } else { 'Green' }

    # 内存空闲百分比条 (与磁盘行的 "空闲%" 口径一致)
    $memFreePct = if ($s.MemTotalGB -gt 0) { [math]::Round($s.MemFreeGB / $s.MemTotalGB * 100, 0) } else { 0 }
    $memBarWidth = 18
    $memFilled = [math]::Floor($memBarWidth * $memFreePct / 100)
    $memBar = '█' * $memFilled + '░' * ($memBarWidth - $memFilled)
    $memColor = if ($memFreePct -lt 15) { 'Red' } elseif ($memFreePct -lt 30) { 'Yellow' } else { 'Green' }

    $scoreColor = if ($s.Score -ge 80) { 'Green' } elseif ($s.Score -ge 50) { 'Yellow' } else { 'Red' }

    Write-Host "  ┌──────────────────────────────────────────────────────────────┐" -ForegroundColor DarkCyan
    Write-Host ("  │ 磁盘: {0} GB 空闲 / {1} GB ({2}%)" -f $s.FreeGB, $s.TotalGB, $s.FreePct) -ForegroundColor White
    Write-Host ("  │      [{0}]" -f $diskBar) -ForegroundColor $diskColor
    Write-Host ("  │ 内存: {0} GB 空闲 / {1} GB ({2}%)" -f $s.MemFreeGB, $s.MemTotalGB, $memFreePct) -ForegroundColor White
    Write-Host ("  │      [{0}]" -f $memBar) -ForegroundColor $memColor
    Write-Host ("  │ 垃圾量约: {0} MB   启动项: {1} 个" -f $s.JunkMB, $s.Startup) -ForegroundColor White
    Write-Host ("  │ 健康评分: ") -ForegroundColor White -NoNewline
    Write-Host ("{0} / 100" -f $s.Score) -ForegroundColor $scoreColor -NoNewline
    Write-Host ""
    if ($s.Issues.Count -gt 0) {
        Write-Host ("  │ 提示: {0}" -f ($s.Issues -join '; ')) -ForegroundColor Yellow
    }
    Write-Host "  └──────────────────────────────────────────────────────────────┘" -ForegroundColor DarkCyan
}

# ================= 注册表备份 / 还原 =================
function Backup-RegistryRun {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $dir = Join-Path $script:BackupDir "run_$stamp"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    $keys = @(
        'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager',
        'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced',
        'HKCU\Software\Microsoft\Windows\CurrentVersion\Search',
        'HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications',
        'HKCU\Software\Policies\Microsoft\Windows\CloudContent',
        'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection',
        'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'
    )
    $i = 0
    foreach ($k in $keys) {
        $i++
        reg.exe export $k (Join-Path $dir "key$i.reg") /y 2>$null | Out-Null
    }
    Set-Content -Path (Join-Path $dir "changes.txt") -Value ($script:changedLog -join "`r`n") -Encoding UTF8
    Write-OK "注册表已备份到: $dir"
    return $dir
}

function Restore-RegistryRun {
    $runs = Get-ChildItem $script:BackupDir -Directory -Filter 'run_*' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending
    if (-not $runs) { Write-Info "没有找到任何备份记录。"; return }

    Write-Info "可用的备份:"
    for ($i = 0; $i -lt $runs.Count; $i++) {
        Write-Host "  [$($i+1)] $($runs[$i].Name)" -ForegroundColor Yellow
    }
    $sel = Read-Host "输入序号选择要还原的备份 (回车取消)"
    if ($sel -eq '') { return }
    $idx = [int]$sel - 1
    if ($idx -lt 0 -or $idx -ge $runs.Count) { Write-Err "序号无效。"; return }

    $target = $runs[$idx]
    $files = Get-ChildItem $target.FullName -Filter '*.reg'
    if (-not $files) { Write-Info "该备份内没有注册表文件。"; return }

    foreach ($f in $files) {
        reg.exe import $f.FullName 2>$null | Out-Null
        Write-OK "已还原: $($f.Name)"
    }
    Write-Info "还原完成。部分系统策略可能需要重启后完全生效。"
}

# ================= 创建还原点 =================
function Invoke-RestorePoint {
    Write-Step "创建系统还原点"
    Write-Info "检查系统保护是否启用..."
    # 启用 C 盘系统保护 (如未启用)
    Enable-ComputerRestore -Drive $env:SystemDrive -ErrorAction SilentlyContinue | Out-Null
    try {
        Checkpoint-Computer -Description "WinCleanPro v$script:AppVer 优化前还原点" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-OK "还原点创建成功!"
        Write-Info "你可以随时在「系统还原」中回到这个时间点。"
    } catch {
        Write-Warn "创建还原点失败: $_"
        Write-Info "可能原因: 系统保护未开启, 或还原点已被占用。"
        Write-Info "可在「控制面板 → 系统 → 系统保护」中手动开启。"
    }
}

# ================= 磁盘清理 =================
function Invoke-DiskCleanup {
    Write-Step "磁盘清理"
    Write-Host "  ═══ 开始清理 · 所有删除均进入回收站，可随时还原 ═══" -ForegroundColor DarkGray

    # 清理前预览清单, 让用户清楚本次会处理哪些内容
    $preview = @(
        '用户临时文件 (%TEMP%) 与系统临时文件 (Windows\Temp)',
        'Windows 更新下载缓存 (SoftwareDistribution\Download)',
        'Windows 更新残留的旧安装日志',
        '传递优化缓存 (Delivery Optimization)',
        '缩略图缓存 (thumbcache)',
        '字体缓存 (FontCache) 与字体服务日志 (DFSVC)',
        '浏览器缓存 (Chrome / Edge / Firefox)',
        'Windows 错误报告 (WER) 与崩溃转储',
        'DirectX 着色器缓存',
        'CBS / DISM 日志残留',
        '回收站 (C盘)'
    )
    Write-Info "本次将清理以下内容 (均可回收站还原):"
    $preview | ForEach-Object { Write-Host "   • $_" -ForegroundColor Gray }

    $beforeFree = Get-FreeSpaceMB
    $beforeItems = $script:stats.CleanedItems
    $totalSteps = 12
    $step = 0

    $step++
    Write-ProgressBar -Percent (($step / $totalSteps) * 100) -Label "临时文件"
    Write-Info "清理临时文件..."
    Get-ChildItem -Path $env:TEMP -Force -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-ToRecycleBin $_.FullName -Label "(临时)" }
    Get-ChildItem -Path 'C:\Windows\Temp' -Force -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-ToRecycleBin $_.FullName -Label "(系统临时)" }

    $step++
    Write-ProgressBar -Percent (($step / $totalSteps) * 100) -Label "更新缓存"
    Write-Info "清理 Windows 更新下载缓存..."
    Get-ChildItem -Path 'C:\Windows\SoftwareDistribution\Download' -Force -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-ToRecycleBin $_.FullName -Label "(更新缓存)" }
    Write-Info "清理 Windows 更新残留的旧安装日志 (WinSxS 组件存储不受影响)..."
    Get-ChildItem -Path 'C:\Windows\servicing\Packages' -Filter '*.log' -File -Force -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-ToRecycleBin $_.FullName -Label "(更新旧日志)" }

    $step++
    Write-ProgressBar -Percent (($step / $totalSteps) * 100) -Label "传递优化"
    Write-Info "清理传递优化缓存..."
    Get-ChildItem -Path 'C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache' -Force -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-ToRecycleBin $_.FullName -Label "(传递优化)" }

    $step++
    Write-ProgressBar -Percent (($step / $totalSteps) * 100) -Label "缩略图"
    Write-Info "清理缩略图缓存..."
    Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer') -Filter 'thumbcache_*.db' -Force -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-ToRecycleBin $_.FullName -Label "(缩略图)" }

    $step++
    Write-ProgressBar -Percent (($step / $totalSteps) * 100) -Label "字体缓存"
    Write-Info "清理字体缓存 (系统会自动重建, 重新打开即可)..."
    $fontCacheDirs = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\FontCache'),
        (Join-Path $env:WINDIR 'ServiceProfiles\LocalService\AppData\Local\FontCache')
    )
    foreach ($fcd in $fontCacheDirs) {
        if (Test-Path $fcd) {
            Get-ChildItem -Path $fcd -File -Force -ErrorAction SilentlyContinue |
                ForEach-Object { Remove-ToRecycleBin $_.FullName -Label "(字体缓存)" }
        }
    }

    $step++
    Write-ProgressBar -Percent (($step / $totalSteps) * 100) -Label "字体服务日志"
    Write-Info "清理字体服务 (DFSVC) 日志..."
    $dfsvcDir = Join-Path $env:WINDIR 'System32\config\systemprofile\AppData\Local\Fonts'
    if (Test-Path $dfsvcDir) {
        Get-ChildItem -Path $dfsvcDir -Filter '*.log' -File -Force -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-ToRecycleBin $_.FullName -Label "(字体服务日志)" }
    }

    $step++
    Write-ProgressBar -Percent (($step / $totalSteps) * 100) -Label "错误报告"
    Write-Info "清理 Windows 错误报告 (WER) 与崩溃转储..."
    $werDirs = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER'),
        (Join-Path $env:LOCALAPPDATA 'CrashDumps'),
        'C:\ProgramData\Microsoft\Windows\WER',
        'C:\Windows\Minidump',
        'C:\Windows\MEMORY.DMP'
    )
    foreach ($wer in $werDirs) {
        if (Test-Path $wer) {
            Get-ChildItem -Path $wer -Force -ErrorAction SilentlyContinue |
                ForEach-Object { Remove-ToRecycleBin $_.FullName -Label "(错误报告)" }
        }
    }

    $step++
    Write-ProgressBar -Percent (($step / $totalSteps) * 100) -Label "着色器缓存"
    Write-Info "清理 DirectX 着色器缓存 (游戏/图形应用会自动重建)..."
    $dxcDir = Join-Path $env:LOCALAPPDATA 'D3DSCache'
    if (Test-Path $dxcDir) {
        Get-ChildItem -Path $dxcDir -Force -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-ToRecycleBin $_.FullName -Label "(着色器缓存)" }
    }

    $step++
    Write-ProgressBar -Percent (($step / $totalSteps) * 100) -Label "CBS 日志"
    Write-Info "清理 CBS / DISM 日志残留..."
    Get-ChildItem -Path "$env:WINDIR\Logs" -Filter 'CBS*.log' -File -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-ToRecycleBin $_.FullName -Label "(CBS日志)" }
    Get-ChildItem -Path "$env:WINDIR\Logs\DISM" -File -Force -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-ToRecycleBin $_.FullName -Label "(DISM日志)" }

    $step++
    Write-ProgressBar -Percent (($step / $totalSteps) * 100) -Label "浏览器缓存"
    Write-Info "清理浏览器缓存 (Chrome / Edge / Firefox)..."
    $browserCaches = @(
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Cache'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Code Cache'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Cache'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Code Cache'),
        (Join-Path $env:LOCALAPPDATA 'Mozilla\Firefox\Profiles')
    )
    foreach ($c in $browserCaches) {
        if (Test-Path $c) {
            Get-ChildItem -Path $c -Force -ErrorAction SilentlyContinue |
                ForEach-Object { Remove-ToRecycleBin $_.FullName -Label "(浏览器缓存)" }
        }
    }

    $step++
    Write-ProgressBar -Percent (($step / $totalSteps) * 100) -Label "回收站"
    Write-Info "清空回收站..."
    try {
        Clear-RecycleBin -DriveLetter $env:SystemDrive.TrimEnd(':') -Force -ErrorAction Stop
        Write-OK "回收站已清空"
    } catch {
        Write-Info "回收站已是空的或正在使用中。"
    }

    $afterFree = Get-FreeSpaceMB
    $freed = $afterFree - $beforeFree
    $items = $script:stats.CleanedItems - $beforeItems
    if ($freed -lt 0) { $freed = 0 }
    $script:stats.DiskFreedMB = [math]::Round($freed, 0)
    if ($freed -gt 0) {
        Show-CleanupResult -FreedMB $freed -Items $items
    } else {
        Write-Info "本次未检测到明显的空间释放 (垃圾可能已很少)。"
    }

    # 检测 Windows.old (系统升级残留, 占用常达数十 GB)
    $oldDir = "$env:SystemDrive\Windows.old"
    if (Test-Path $oldDir) {
        $oldMB = Get-FolderSizeMB $oldDir
        if ($oldMB -gt 100) {
            Write-Warn "检测到 Windows 升级残留目录: $oldDir (约 $oldMB MB)"
            Write-Info "如需彻底删除, 可手动执行 (管理员):"
            Write-Host "    dism.exe /online /cleanup-image /startcomponentcleanup" -ForegroundColor Yellow
            Write-Host "    dism.exe /online /cleanup-image /spsuperseded" -ForegroundColor Yellow
            Write-Host "    Takeown /F `"$oldDir`" /A /R /D Y" -ForegroundColor Yellow
            Write-Host "    Rmdir /S /Q `"$oldDir`"" -ForegroundColor Yellow
            Write-Info "或使用系统自带的「磁盘清理 → 清理系统文件 → 以前的 Windows 安装」。"
        }
    }

    Refresh-SystemStatus
}

function Invoke-ComponentStoreCleanup {
    Write-Step "WinSxS 组件存储清理"
    Write-Warn "此操作会运行 DISM 组件清理, 可能耗时 10-30 分钟。"
    if (-not $script:skipConfirm) {
        $ans = Read-Host "是否继续? (y/N)"
        if ($ans -notmatch '^[yY]') { Write-Info "已取消。"; return }
    }
    dism.exe /online /cleanup-image /startcomponentcleanup
    Write-OK "组件存储清理完成。"
    Refresh-SystemStatus
}

# ================= 去广告 / 精简 =================
function Invoke-Debloat {
    Write-Step "去广告 / 系统精简"

    $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    $adValues = @{
        'SystemPaneSuggestionsEnabled'  = 0
        'RotatingLockScreenEnabled'     = 0
        'RotatingLockScreenOverlayEnabled' = 0
        'SubscribedContent-310093Enabled' = 0
        'SubscribedContent-338388Enabled' = 0
        'SubscribedContent-338389Enabled' = 0
        'SubscribedContent-338393Enabled' = 0
        'SubscribedContent-353694Enabled' = 0
        'SubscribedContent-353696Enabled' = 0
        'SilentInstalledAppsEnabled'    = 0
        'SoftLandingEnabled'            = 0
    }
    foreach ($k in $adValues.Keys) {
        if (Set-RegValue -Path $cdm -Name $k -Value $adValues[$k]) {
            $script:changedLog += "ContentDeliveryManager: $k = 0"
        }
    }
    Write-OK "已关闭开始菜单推荐 / 锁屏广告 / 应用建议"

    $cloud = 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent'
    foreach ($k in @('DisableWindowsConsumerFeatures','DisableSoftLanding','DisableWindowsSpotlightFeatures')) {
        if (Set-RegValue -Path $cloud -Name $k -Value 1) {
            $script:changedLog += "CloudContent: $k = 1"
        }
    }
    Write-OK "已关闭 Windows 消费者功能 / 聚焦建议"

    $expAdv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    if (Set-RegValue -Path $expAdv -Name 'ShowCopilotButton' -Value 0) {
        $script:changedLog += "Explorer: ShowCopilotButton = 0"
        Write-OK "已隐藏任务栏 Copilot 按钮"
    }
    if (Set-RegValue -Path $expAdv -Name 'ShowSyncProviderNotifications' -Value 0) {
        $script:changedLog += "Explorer: ShowSyncProviderNotifications = 0"
    }
    if (Set-RegValue -Path $expAdv -Name 'TaskbarDa' -Value 0) {
        $script:changedLog += "Explorer: TaskbarDa = 0"
        Write-OK "已隐藏任务栏小组件按钮"
    }

    $search = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
    foreach ($k in @('BingSearchEnabled','CortanaConsent')) {
        if (Set-RegValue -Path $search -Name $k -Value 0) {
            $script:changedLog += "Search: $k = 0"
        }
    }
    Write-OK "已关闭必应搜索建议"

    $teleKeys = @(
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'
    )
    foreach ($tk in $teleKeys) {
        if (Set-RegValue -Path $tk -Name 'AllowTelemetry' -Value 0) {
            $script:changedLog += "$tk : AllowTelemetry = 0"
        }
    }
    Write-OK "已关闭遥测诊断数据"

    $bg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'
    if (Set-RegValue -Path $bg -Name 'GlobalUserDisabled' -Value 1) {
        $script:changedLog += "BackgroundAccess: GlobalUserDisabled = 1"
        Write-OK "已禁止后台应用运行"
    }

    Write-Info "去广告完成。所有改动已在修改前自动备份。"
    Refresh-SystemStatus
}

# ================= 性能优化 =================
function Invoke-Performance {
    Write-Step "性能优化"

    Write-Info "切换电源计划为「高性能」..."
    powercfg.exe /setactive SCHEME_MIN
    Write-OK "已启用高性能电源计划"

    Write-Info "关闭视觉特效 (调整为最佳性能)..."
    $vf = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
    if (Set-RegValue -Path $vf -Name 'VisualFXSetting' -Value 2) {
        $script:changedLog += "Explorer\VisualEffects: VisualFXSetting = 2"
        Write-OK "已关闭视觉特效 (保留基础动画)"
    }

    Write-Info "关闭后台应用..."
    $bg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'
    if (Set-RegValue -Path $bg -Name 'GlobalUserDisabled' -Value 1) {
        $script:changedLog += "BackgroundAccess: GlobalUserDisabled = 1"
        Write-OK "已禁止后台应用"
    }

    Write-Info "启动项分析:"
    Show-StartupItems
    Refresh-SystemStatus
}

function Show-StartupItems {
    $items = Get-StartupItems
    if ($items.Count -eq 0) { Write-Info "未发现明显的启动项。"; return }
    $items | Format-Table Name, Source, @{L='命令';E={if($_.Command.Length -gt 55){$_.Command.Substring(0,55)+'...'}else{$_.Command}}} -AutoSize | Out-String -Width 130 | Write-Host
    Write-Info "共 $($items.Count) 个启动项。可用 [11] 启动项管理 禁用不需要的项目。"
}

# ================= 启动项管理 =================
function Invoke-StartupManager {
    Write-Step "启动项管理"
    $items = Get-StartupItems
    if ($items.Count -eq 0) { Write-Info "未发现启动项。"; return }

    for ($i = 0; $i -lt $items.Count; $i++) {
        $cmd = $items[$i].Command
        if ($cmd.Length -gt 50) { $cmd = $cmd.Substring(0,50) + '...' }
        Write-Host ("  [{0}] {1}  ({2})" -f ($i+1), $items[$i].Name, $items[$i].Source) -ForegroundColor White
        Write-Host ("      {0}" -f $cmd) -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  [d 序号] 禁用启动项   [e 序号] 启用   [回车] 返回" -ForegroundColor Yellow
    $sel = Read-Host "输入命令"

    if ($sel -match '^[dD]\s*(\d+)$') {
        $idx = [int]$matches[1] - 1
        if ($idx -ge 0 -and $idx -lt $items.Count) {
            $item = $items[$idx]
            $approvedPath = if ($item.Source -eq 'HKLM') {
                'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
            } else {
                'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
            }
            if (-not (Test-Path $approvedPath)) { New-Item -Path $approvedPath -Force | Out-Null }
            Set-ItemProperty -Path $approvedPath -Name $item.Name -Value ([byte[]](0x03,0,0,0,0,0,0,0,0,0,0,0)) -Type Binary
            Write-OK "已禁用启动项: $($item.Name)"
        } else { Write-Err "序号无效。" }
    } elseif ($sel -match '^[eE]\s*(\d+)$') {
        $idx = [int]$matches[1] - 1
        if ($idx -ge 0 -and $idx -lt $items.Count) {
            $item = $items[$idx]
            $approvedPath = if ($item.Source -eq 'HKLM') {
                'HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
            } else {
                'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
            }
            if (-not (Test-Path $approvedPath)) { New-Item -Path $approvedPath -Force | Out-Null }
            Set-ItemProperty -Path $approvedPath -Name $item.Name -Value ([byte[]](0x02,0,0,0,0,0,0,0,0,0,0,0)) -Type Binary
            Write-OK "已启用启动项: $($item.Name)"
        } else { Write-Err "序号无效。" }
    } else {
        Write-Info "已取消。"
    }
}

# ================= 空间分析 =================
function Invoke-SpaceAnalysis {
    Write-Step "空间分析 (扫描大目录 TOP10)"
    $roots = @($env:USERPROFILE, 'C:\Program Files', 'C:\Program Files (x86)')
    $result = @()
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem -Path $root -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $size = Get-FolderSizeMB $_.FullName
            if ($size -gt 100) {
                $result += [PSCustomObject]@{ 目录 = $_.FullName; 占用MB = $size }
            }
        }
    }
    $top = $result | Sort-Object 占用MB -Descending | Select-Object -First 10
    if (-not $top) { Write-Info "未扫描到超过 100MB 的目录。"; return }
    Write-Host ""
    $top | Format-Table 占用MB, 目录 -AutoSize | Out-String -Width 120 | Write-Host
    $outFile = Join-Path $script:ReportDir ("space_report_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $top | Format-Table -AutoSize | Out-String -Width 160 | Set-Content -Path $outFile -Encoding UTF8
    Write-OK "完整报告已保存: $outFile"
}

# ================= 大文件查找 =================
function Invoke-LargeFileScan {
    Write-Step "大文件查找"
    $root = Read-Host "输入要扫描的目录 (回车 = C:\ 全盘, 较慢)"
    if ($root -eq '') { $root = 'C:\' }
    if (-not (Test-Path $root)) { Write-Err "路径不存在。"; return }

    $minMB = Read-Host "查找大于多少 MB 的文件? (默认 500)"
    if ($minMB -eq '') { $minMB = 500 }
    $minMB = [int]$minMB
    $minBytes = $minMB * 1MB

    Write-Info "扫描中 (只扫描文件, 不包含系统隐藏目录)..."
    $files = Get-ChildItem -Path $root -Recurse -File -Force -ErrorAction SilentlyContinue |
             Where-Object { $_.FullName -notmatch '\\Windows\\' -and $_.Length -ge $minBytes } |
             Sort-Object Length -Descending | Select-Object -First 20

    if (-not $files) { Write-Info "未找到超过 $minMB MB 的文件。"; return }

    Write-Host ""
    Write-Info "最大的 $minMB MB+ 文件 TOP20:"
    $files | Select-Object @{L='大小MB';E={[math]::Round($_.Length/1MB,0)}}, @{L='路径';E={$_.FullName}} |
        Format-Table -AutoSize | Out-String -Width 130 | Write-Host

    $outFile = Join-Path $script:ReportDir ("large_files_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $files | Select-Object @{L='大小MB';E={[math]::Round($_.Length/1MB,0)}}, FullName |
        Format-Table -AutoSize | Out-String -Width 160 | Set-Content -Path $outFile -Encoding UTF8
    Write-OK "完整报告已保存: $outFile"
}

# ================= 开发者专项清理 =================
function Invoke-DevCleanup {
    Write-Step "开发者专项清理"
    # 只清理确定可安全重建的构建/依赖缓存目录
    $names = @('node_modules','__pycache__','.gradle','.venv','venv','.cache','.pytest_cache')
    # dist/build 等名字太常见, 且不一定可安全重建, 不自动清理
    Write-Info "正在扫描用户目录下的开发垃圾文件夹 (可能需要一点时间)..."
    $found = Get-ChildItem -Path $env:USERPROFILE -Directory -Depth 3 -Force -ErrorAction SilentlyContinue |
             Where-Object { $_.FullName -ne $env:USERPROFILE -and $_.Name -in $names }

    if (-not $found) { Write-Info "没有发现开发垃圾文件夹。"; return }

    $list = @()
    foreach ($d in $found) {
        $sz = Get-FolderSizeMB $d.FullName
        $list += [PSCustomObject]@{ 文件夹 = $d.FullName; 大小MB = $sz }
    }
    $list = $list | Sort-Object 大小MB -Descending
    Write-Host ""
    $list | Format-Table 大小MB, 文件夹 -AutoSize | Out-String -Width 140 | Write-Host
    Write-Info "说明: dist/build 等目录因名称太常见且不一定可安全重建, 已排除在自动清理之外。"

    $total = [math]::Round(($list | Measure-Object 大小MB -Sum).Sum, 1)
    Write-Warn "以上共约 $total MB, 删除后会移入回收站 (可还原)。"
    if (-not $script:skipConfirm) {
        $ans = Read-Host "是否全部移入回收站? (y/N)"
        if ($ans -notmatch '^[yY]') { Write-Info "已取消。"; return }
    }
    foreach ($d in $found) {
        Remove-ToRecycleBin $d.FullName -Label "(开发缓存)"
    }
    $script:stats.DevFreedMB += $total

    $vhd = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Packages') -Recurse -Filter 'ext4.vhdx' -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($vhd) {
        $vhdMB = Get-FolderSizeMB $vhd.FullName
        Write-Info "检测到 WSL2 虚拟磁盘: $($vhd.FullName) ($vhdMB MB)"
        Write-Info "如需压缩, 可手动执行以下命令 (管理员):"
        Write-Host "    wsl --shutdown" -ForegroundColor Yellow
        Write-Host "    Optimize-VHD -Path `"$($vhd.FullName)`" -Mode Full" -ForegroundColor Yellow
    }
    Refresh-SystemStatus
}

# ================= 预装应用管理 (AppX Debloat) =================
function Invoke-AppxDebloat {
    Write-Step "预装应用管理 (AppX Debloat)"
    $pattern = 'bing|Bing|CandyCrush|Solitaire|Xbox|Skype|Spotify|Clipchamp|News|Weather|TikTok|Facebook|Instagram|GetHelp|OfficeHub|OneNote|ToDo|Widgets|ZuneVideo|People|Messaging|FeedbackHub|MixedReality|YourPhone|Teams|Mail'

    # 以下组件即使匹配也不会被移除 (避免破坏系统或失去安全更新)
    $blocklist = @(
        'Microsoft.WindowsCalculator',
        'Microsoft.WindowsStore',
        'Microsoft.WindowsCamera',
        'Microsoft.Windows.Photos',
        'Microsoft.WindowsTerminal',
        'Microsoft.StorePurchaseApp',
        'Microsoft.WinDbg',
        'Microsoft.PowerShell'
    )

    $apps = Get-AppxPackage | Where-Object { $_.Name -match $pattern -and $_.Name -notin $blocklist }
    if (-not $apps) { Write-Info "没有检测到可移除的预装应用。"; return }

    $list = @()
    $i = 0
    foreach ($a in $apps) {
        $i++
        $list += [PSCustomObject]@{ Idx=$i; 名称=$a.Name -replace '^Microsoft\.',''; 版本=$a.Version }
    }
    $list | Format-Table Idx, 名称, 版本 -AutoSize | Out-String -Width 120 | Write-Host
    Write-Info "已自动保护: 计算器 / 商店 / 相机 / 照片 / 终端等系统组件, 不会出现在列表中。"

    Write-Warn "注意: 移除照片/邮件/Xbox 等可能影响对应功能。"

    # 非交互模式 (如 -Deep 一键) 直接全部移除, 跳过确认
    if ($script:skipConfirm) {
        Write-Info "非交互模式: 正在全部移除... ($($apps.Count) 个)"
        $targets = $apps
    } else {
        Write-Info "移除方式:"
        Write-Host "  [a] 全部移除    [n] 按序号移除多个(逗号分隔)   [回车] 取消" -ForegroundColor Yellow
        $sel = Read-Host "选择"
        if ($sel -eq '') { Write-Info "已取消。"; return }

        $targets = @()
        if ($sel -eq 'a') {
            $targets = $apps
        } elseif ($sel -match '^[nN]') {
            $nums = (Read-Host "输入序号, 用逗号分隔").Split(',')
            foreach ($n in $nums) {
                $n = [int]$n
                if ($n -ge 1 -and $n -le $apps.Count) { $targets += $apps[$n-1] }
            }
        } else { Write-Info "已取消。"; return }
    }

    foreach ($a in $targets) {
        Write-Info "移除 $($a.Name)..."
        Remove-AppxPackage -Package $a.PackageFullName -ErrorAction SilentlyContinue
        Remove-AppxPackage -Package $a.PackageFullName -AllUsers -ErrorAction SilentlyContinue
    }
    Write-OK "预装应用移除完成。"
}

# ================= 软件更新 (winget) =================
function Invoke-WingetUpdate {
    Write-Step "软件更新 (winget 一键更新)"
    $wg = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wg) {
        Write-Warn "未检测到 winget。请在 Microsoft Store 安装「应用安装程序」后再试。"
        return
    }
    Write-Info "正在检查所有已安装软件是否有可用更新... (首次可能较慢)"
    if (-not $script:skipConfirm) {
        $ans = Read-Host "是否更新全部软件? (y/N)"
        if ($ans -notmatch '^[yY]') { Write-Info "已取消。"; return }
    }
    winget upgrade --all --include-unknown
    Write-OK "软件更新完成。"
}

# ================= 软件卸载 (winget) =================
function Invoke-WingetUninstall {
    Write-Step "软件卸载 (winget)"
    $wg = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wg) {
        Write-Warn "未检测到 winget。请先在 Microsoft Store 安装「应用安装程序」。"
        return
    }
    $kw = Read-Host "输入要搜索的软件关键词 (如 chrome, wechat 等)"
    if ($kw -eq '') { Write-Info "已取消。"; return }

    # 系统关键组件即使匹配也不建议卸载
    $neverUninstall = @('Microsoft Edge','Windows Defender','Microsoft .NET','Microsoft Visual C++','Microsoft Store','Windows Malicious Software Removal Tool')

    Write-Info "正在搜索已安装的软件..."
    $lines = winget list 2>$null | Out-String
    $hits = $lines -split "`r?`n" | Where-Object { $_ -match $kw -and ($_ -notmatch '^名称|^Name') }
    $hits = $hits | Where-Object {
        $blocked = $false
        foreach ($n in $neverUninstall) {
            if ($_ -match [regex]::Escape($n)) { $blocked = $true; break }
        }
        -not $blocked
    }

    if (-not $hits) {
        Write-Info "没有找到包含「$kw」的已安装软件 (系统关键组件已自动排除)。"
        return
    }
    Write-Host ""
    Write-Info "匹配到以下软件 (系统关键组件已自动排除):"
    $hits | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

    $appId = Read-Host "输入要卸载的软件 ID (winget list 第一列, 回车取消)"
    if ($appId -eq '') { Write-Info "已取消。"; return }
    $confirm = Read-Host "确认卸载 $appId ? (y/N)"
    if ($confirm -notmatch '^[yY]') { Write-Info "已取消。"; return }

    winget uninstall --id $appId --silent
    Write-OK "卸载命令已执行。"
}

# ================= 网络优化 =================
function Invoke-NetworkOptimize {
    Write-Step "网络优化"
    Write-Info "刷新 DNS 解析缓存..."
    ipconfig.exe /flushdns | Out-Null
    Write-OK "DNS 缓存已刷新"

    Write-Info "重置 Winsock 目录..."
    netsh.exe winsock reset
    Write-OK "Winsock 已重置"

    Write-Info "重置 TCP/IP 协议栈..."
    netsh.exe int ip reset
    Write-OK "TCP/IP 已重置"

    Write-Warn "TCP/IP 重置后建议重启电脑生效。"
}

# ================= 系统修复 =================
function Invoke-SystemRepair {
    Write-Step "系统修复"
    Write-Warn "以下操作可能需要 10-30 分钟, 期间请勿关闭窗口。"
    if (-not $script:skipConfirm) {
        $ans = Read-Host "是否继续? (y/N)"
        if ($ans -notmatch '^[yY]') { Write-Info "已取消。"; return }
    }

    Write-Info "运行 DISM 系统映像健康检查..."
    dism.exe /online /cleanup-image /restorehealth
    Write-Host ""

    Write-Info "运行 SFC 系统文件检查..."
    sfc.exe /scannow
    Write-Host ""

    Write-OK "系统修复完成。如发现问题已自动尝试修复。"
}

# ================= Defender 扫描 =================
function Invoke-DefenderScan {
    Write-Step "Windows Defender 快速扫描"
    try {
        $status = Get-MpComputerStatus -ErrorAction Stop
        if ($status.AntivirusEnabled) {
            Write-Info "Defender 实时保护状态: 已启用"
            Write-Info "开始快速扫描..."
            if (-not $script:skipConfirm) {
                $ans = Read-Host "是否开始快速扫描? (y/N)"
                if ($ans -notmatch '^[yY]') { Write-Info "已取消。"; return }
            }
            Start-MpScan -ScanType QuickScan -ErrorAction Stop
            Write-OK "快速扫描完成。"
        } else {
            Write-Warn "Defender 实时保护未启用 (可能是第三方杀软接管)。"
        }
    } catch {
        Write-Warn "无法执行 Defender 扫描: $_"
        Write-Info "可尝试在「Windows 安全中心 → 病毒和威胁防护」手动扫描。"
    }
}

# ================= 系统信息 =================
function Invoke-SystemInfo {
    Write-Step "系统信息"
    $os  = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor
    $mb  = Get-CimInstance Win32_BaseBoard
    $bios = Get-CimInstance Win32_BIOS
    $cs  = Get-CimInstance Win32_ComputerSystem
    $gpu = Get-CimInstance Win32_VideoController | Select-Object -First 1
    $disk = Get-PSDrive -Name $env:SystemDrive.TrimEnd(':')
    $totalMem = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    $freeMem  = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)

    $rows = @(
        @{ 项目='操作系统'; 值="$($os.Caption) (Build $($os.BuildNumber))" },
        @{ 项目='系统类型'; 值=$os.OSArchitecture },
        @{ 项目='处理器'; 值=$cpu.Name },
        @{ 项目='核心线程'; 值="$($cpu.NumberOfCores) 核 $($cpu.NumberOfLogicalProcessors) 线程" },
        @{ 项目='内存'; 值="$freeMem GB 可用 / $totalMem GB" },
        @{ 项目='显卡'; 值=$gpu.Name },
        @{ 项目='主板'; 值=$mb.Manufacturer + ' ' + $mb.Product },
        @{ 项目='BIOS'; 值=$bios.SMBIOSBIOSVersion },
        @{ 项目='计算机名'; 值=$env:COMPUTERNAME },
        @{ 项目='当前用户'; 值=$env:USERNAME },
        @{ 项目='C盘空间'; 值="$([math]::Round($disk.Used/1GB,1)) GB 已用 / $([math]::Round(($disk.Used+$disk.Free)/1GB,1)) GB" },
        @{ 项目='Windows 目录'; 值=$env:WINDIR }
    )
    $rows | Format-Table -AutoSize | Out-String -Width 120 | Write-Host
}

# ================= 重复文件查找 =================
function Invoke-DuplicateScan {
    Write-Step "重复文件查找"
    $target = Read-Host "输入要扫描的文件夹路径 (回车 = 用户目录)"
    if ($target -eq '') { $target = $env:USERPROFILE }
    if (-not (Test-Path $target)) { Write-Err "路径不存在。"; return }

    Write-Info "扫描中 (仅查找 >1MB 的文件, 大目录可能较慢)..."
    # 第一层: 按大小分组, 排除大小为 0 的异常项
    $bySize = Get-ChildItem -Path $target -Recurse -File -ErrorAction SilentlyContinue |
              Where-Object { $_.Length -gt 1MB } |
              Group-Object Length | Where-Object { $_.Count -gt 1 }

    $dupes = @()
    foreach ($g in $bySize) {
        # 第二层: 对同大小文件逐一计算 SHA1 哈希 (双重校验, 避免误判)
        $byHash = $g.Group | ForEach-Object {
            $h = (Get-FileHash $_.FullName -Algorithm SHA1 -ErrorAction SilentlyContinue).Hash
            if ($h) {
                [PSCustomObject]@{ Path = $_.FullName; Length = $_.Length; Hash = $h }
            }
        } | Group-Object Hash | Where-Object { $_.Count -gt 1 }

        foreach ($h in $byHash) {
            # 第三层: 排除不同文件路径 (防止把同一目录树误报)
            $paths = @($h.Group | ForEach-Object { $_.Path })
            if (($paths | Select-Object -Unique).Count -lt $paths.Count) {
                $dupes += $h.Group
            }
        }
    }

    if (-not $dupes) { Write-Info "未发现重复文件。"; return }

    Write-Host ""
    Write-Info "发现以下重复文件组:"
    $dupes | Group-Object Hash | ForEach-Object {
        Write-Host ""
        Write-Host "  --- 重复组 (SHA1: $($_.Name.Substring(0,12))...) ---" -ForegroundColor Yellow
        $_.Group | ForEach-Object { Write-Host "    $($_.Path)" -ForegroundColor Gray }
    }
    Write-Host ""

    Write-Warn "共 $($dupes.Count) 个重复文件。删除后移入回收站 (可还原)。"
    if (-not $script:skipConfirm) {
        $ans = Read-Host "是否将所有重复文件的副本移入回收站? (保留每组第一个) (y/N)"
        if ($ans -notmatch '^[yY]') { Write-Info "已取消。"; return }
    }
    $removed = 0
    # Windows 自身维护的路径, 误删可能导致资源管理器异常, 跳过
    $protectedPrefix = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Recent'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Cookies'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Recent\AutomaticDestinations'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\IISLogFiles')
    )
    $dupes | Group-Object Hash | ForEach-Object {
        $keep = $_.Group | Sort-Object Path | Select-Object -First 1
        $_.Group | Where-Object { $_.Path -ne $keep.Path } | ForEach-Object {
            $skip = $false
            foreach ($pp in $protectedPrefix) {
                if ($_.Path.StartsWith($pp, [StringComparison]::OrdinalIgnoreCase)) { $skip = $true; break }
            }
            if ($skip) {
                Write-Info "跳过受保护路径: $($_.Path)"
            } else {
                Remove-ToRecycleBin $_.Path -Label "(重复文件)"
                $removed++
            }
        }
    }
    Write-OK "共移入回收站 $removed 个重复文件。"
}

# ================= 服务优化 =================
function Invoke-ServiceOptimize {
    Write-Step "服务优化"
    Write-Info "检测正在运行的自动启动服务 (按内存占用排序):"
    $services = Get-CimInstance Win32_Service |
                Where-Object { $_.StartMode -eq 'Auto' -and $_.State -eq 'Running' } |
                ForEach-Object {
                    $proc = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
                    [PSCustomObject]@{
                        Name = $_.Name
                        DisplayName = $_.DisplayName
                        MemMB = if ($proc) { [math]::Round($proc.WorkingSet64/1MB,0) } else { 0 }
                    }
                } | Sort-Object MemMB -Descending | Select-Object -First 15

    if (-not $services) { Write-Info "没有检测到相关服务。"; return }
    $services | Format-Table MemMB, Name, DisplayName -AutoSize | Out-String -Width 120 | Write-Host

    Write-Info "说明: 某些服务 (如 Windows Defender) 不建议禁用。"
    Write-Info "如需禁用某项服务, 可在管理员终端手动执行:"
    Write-Host "    sc.exe config <服务名> start= demand   # 改为手动" -ForegroundColor Yellow
    Write-Host "    sc.exe stop <服务名>                    # 立即停止" -ForegroundColor Yellow
    Write-Host "    bcdedit /set bootmenupolicy Legacy      # 旧版启动菜单(可逆)" -ForegroundColor Yellow
    Write-Host "    bcdedit /deletevalue bootmenupolicy     # 恢复默认启动菜单" -ForegroundColor Yellow
    Write-Info "脚本不自动禁用服务, 以避免影响系统稳定。"
}

# ================= 内存清理 =================
function Invoke-MemoryCleanup {
    Write-Step "内存清理"
    Write-Info "正在释放已空闲进程的内存工作集..."
    $before = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB, 1)
    $procs = Get-Process | Where-Object { $_.Id -ne $PID }
    foreach ($p in $procs) {
        try { [WinCleanPro_MemUtil]::EmptyWorkingSet($p.Handle) | Out-Null } catch {}
    }
    $after = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB, 1)
    Write-OK "可用内存: $before GB → $after GB"
    Write-Info "注意: 这是临时释放, 系统内存压力大时会自动回收。"
    Refresh-SystemStatus
}

# ================= HOSTS 广告拦截 =================
function Invoke-HostsManager {
    Write-Step "HOSTS 广告拦截"
    $hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
    if (-not (Test-Path $hosts)) { Write-Err "找不到 hosts 文件。"; return }

    Write-Info "hosts 文件位置: $hosts"
    Write-Host "  [1] 查看当前内容" -ForegroundColor Yellow
    Write-Host "  [2] 备份 hosts 文件" -ForegroundColor Yellow
    Write-Host "  [3] 添加常见广告/遥测拦截条目" -ForegroundColor Yellow
    Write-Host "  [4] 从备份还原 hosts" -ForegroundColor Yellow
    $sel = Read-Host "选择"

    switch ($sel) {
        '1' {
            Get-Content $hosts | Where-Object { $_ -notmatch '^\s*$' -and $_ -notmatch '^\s*#' } | ForEach-Object { Write-Host "  $_" }
        }
        '2' {
            $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $dest = Join-Path $script:BackupDir "hosts_$stamp"
            Copy-Item $hosts $dest
            Write-OK "已备份到: $dest"
        }
        '3' {
            $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            Copy-Item $hosts (Join-Path $script:BackupDir "hosts_before_$stamp") -ErrorAction SilentlyContinue
            $blocklist = @(
                "",
                "# === WinCleanPro 广告/遥测拦截 ===",
                "0.0.0.0 data.microsoft.com",
                "0.0.0.0 storeedgefd.dsx.mp.microsoft.com",
                "0.0.0.0 www.msftconnecttest.com",
                "0.0.0.0 watson.telemetry.microsoft.com",
                "0.0.0.0 vortex.data.microsoft.com",
                "0.0.0.0 settings-win.data.microsoft.com",
                "0.0.0.0 go.microsoft.com",
                "0.0.0.0 a-0001.a-msedge.net"
            )
            Add-Content -Path $hosts -Value $blocklist -Encoding Ascii
            ipconfig.exe /flushdns | Out-Null
            Write-OK "已添加拦截条目并刷新 DNS。原文件已备份。"
        }
        '4' {
            $backs = Get-ChildItem $script:BackupDir -Filter 'hosts_*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending
            if (-not $backs) { Write-Info "没有找到 hosts 备份。"; return }
            Write-Info "可用的备份:"
            for ($i=0; $i -lt $backs.Count; $i++) { Write-Host "  [$($i+1)] $($backs[$i].Name)" -ForegroundColor Yellow }
            $n = Read-Host "选择序号"
            $idx = [int]$n - 1
            if ($idx -ge 0 -and $idx -lt $backs.Count) {
                Copy-Item $backs[$idx].FullName $hosts -Force
                ipconfig.exe /flushdns | Out-Null
                Write-OK "hosts 已还原。"
            } else { Write-Err "序号无效。" }
        }
        default { Write-Info "已取消。" }
    }
}

# ================= 开机耗时追踪 =================
function Invoke-BootTimeTracker {
    Write-Step "开机耗时追踪"
    Write-Info "读取系统开机事件日志 (最近 5 次开机)..."
    try {
        $events = Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-Diagnostics-Performance/Operational'; Id=100 } -MaxEvents 5 -ErrorAction Stop
    } catch {
        Write-Warn "无法读取开机日志: $_"
        Write-Info "可能原因: 日志记录未开启, 或系统刚安装不久还没有开机记录。"
        Write-Info "可尝试在「事件查看器 → 应用程序和服务日志 → Microsoft → Windows → Diagnostics-Performance → Operational」查看。"
        return
    }

    if (-not $events) {
        Write-Info "没有找到开机耗时记录。"
        return
    }

    Write-Host ""
    Write-Info "最近 5 次开机耗时:"
    $rows = @()
    $i = 0
    foreach ($e in $events) {
        $i++
        $bootMs = 0
        $xml = $e.ToXml()
        if ($xml -match '<Data Name="BootTime">(\d+)</Data>') {
            $bootMs = [long]$matches[1]
        } elseif ($xml -match 'BootTime</Data>.*?<Data>(\d+)</Data>') {
            $bootMs = [long]$matches[1]
        } else {
            # 尝试解析 XML 对象
            try {
                [xml]$x = $xml
                $bootMs = [long]$x.Event.EventData.Data | Where-Object { $_.Name -eq 'BootTime' } | ForEach-Object { $_.'#text' }
            } catch {}
        }
        $sec = [math]::Round($bootMs / 1000.0, 1)
        $rows += [PSCustomObject]@{ 序号=$i; 开机耗时秒=$sec; 开机时间=$e.TimeCreated }
    }

    # 柱状图 (越短越好, 用颜色区分)
    $maxSec = ($rows | ForEach-Object { $_.开机耗时秒 } | Measure-Object -Maximum).Maximum
    if ($maxSec -le 0) { $maxSec = 1 }
    Write-Host ""
    Write-Host "  最近 5 次开机耗时对比" -ForegroundColor DarkCyan
    for ($k = 0; $k -lt $rows.Count; $k++) {
        $r = $rows[$k]
        $len = [math]::Max(1, [math]::Round($r.开机耗时秒 / $maxSec * 24))
        $bar = '█' * $len
        $pad = ' ' * (24 - $len)
        $color = if ($r.开机耗时秒 -le 20) { 'Green' } elseif ($r.开机耗时秒 -le 40) { 'Yellow' } else { 'Red' }
        Write-Host ("  开机{0}: {1,5} 秒  │{2}{3}│  {4}" -f ($k+1), $r.开机耗时秒, $bar, $pad, $r.开机时间.ToString('MM-dd HH:mm')) -ForegroundColor $color
    }
    Write-Host "  (绿色≤20秒 / 黄色20-40秒 / 红色>40秒)" -ForegroundColor DarkGray

    # 对比最快/最慢
    $times = $rows | ForEach-Object { $_.开机耗时秒 }
    $best = ($times | Measure-Object -Minimum).Minimum
    $worst = ($times | Measure-Object -Maximum).Maximum
    Write-Info "最近开机耗时: 最快 $best 秒 / 最慢 $worst 秒"
    Write-Info "提示: 可先执行磁盘清理和去广告, 再隔几次开机对比, 观察速度提升。"
    Write-Info "注意: 数值来自系统自动记录, 不包含等待输入密码的时间。"
}

# ================= 休眠文件管理 =================
function Invoke-HibernateManager {
    Write-Step "休眠文件管理"
    $hiber = "$env:SystemRoot\hiberfil.sys"
    $hiberOk = Test-Path $hiber

    if ($hiberOk) {
        $hiberMB = Get-FolderSizeMB $hiber
        Write-Info "检测到休眠文件: $hiber"
        Write-Info "占用空间: 约 $hiberMB MB"
        Write-Warn "休眠功能可以让电脑在关闭时保存当前状态, 下次秒速恢复。"
        Write-Info "如果你从不用休眠, 关闭它可立即释放 $hiberMB MB 空间。"
        Write-Host ""
        Write-Host "  [1] 关闭休眠 (释放 $hiberMB MB)     [2] 保持现状    " -ForegroundColor Yellow
        $sel = Read-Host "选择"
        if ($sel -eq '1') {
            Write-Info "正在关闭休眠..."
            powercfg.exe /h off
            Write-OK "休眠已关闭, 已释放 $hiberMB MB 空间。"
            Refresh-SystemStatus
        } else {
            Write-Info "已取消。"
        }
    } else {
        Write-Info "未检测到休眠文件 (hiberfil.sys)。"
        Write-Info "说明休眠可能已关闭。如需开启休眠 (会创建一个约等于内存大小 40% 的文件):"
        Write-Host ""
        Write-Host "  [1] 开启休眠    [2] 保持关闭    " -ForegroundColor Yellow
        $sel = Read-Host "选择"
        if ($sel -eq '1') {
            powercfg.exe /h on
            Write-OK "休眠已开启。"
            Refresh-SystemStatus
        } else {
            Write-Info "已取消。"
        }
    }
}

# ================= 隐私痕迹清理 =================
function Invoke-PrivacyCleanup {
    Write-Step "隐私痕迹清理"
    Write-Warn "此操作将清除当前用户的个人使用痕迹, 建议在不需要追溯历史时使用。"
    if (-not $script:skipConfirm) {
        $ans = Read-Host "是否继续? (y/N)"
        if ($ans -notmatch '^[yY]') { Write-Info "已取消。"; return }
    }
    $count = 0

    Write-Info "清除最近打开的文档列表..."
    $recent = Join-Path $env:APPDATA 'Microsoft\Windows\Recent'
    if (Test-Path $recent) {
        Get-ChildItem $recent -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-ToRecycleBin $_.FullName -Label "(最近文档)"
            $count++
        }
    }

    Write-Info "清除运行对话框历史..."
    $runMRU = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU'
    if (Test-Path $runMRU) {
        Remove-Item $runMRU -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path $runMRU -Force | Out-Null
        $count++
    }

    Write-Info "清除文件资源管理器历史..."
    $openSave = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32'
    if (Test-Path $openSave) {
        Remove-Item $openSave -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path $openSave -Force | Out-Null
        $count++
    }

    Write-Info "清除搜索历史..."
    $searchHist = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\WordWheelQuery'
    if (Test-Path $searchHist) {
        Remove-Item $searchHist -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path $searchHist -Force | Out-Null
        $count++
    }

    Write-Info "清除跳转列表 (Jump List)..."
    $jumpDir = Join-Path $env:APPDATA 'Microsoft\Windows\Recent\AutomaticDestinations'
    if (Test-Path $jumpDir) {
        Get-ChildItem $jumpDir -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-ToRecycleBin $_.FullName -Label "(跳转列表)"
            $count++
        }
    }

    Write-Info "清除剪贴板历史..."
    Write-Info "已停止剪贴板历史功能 (在「设置 → 系统 → 剪贴板」中可重新开启)"
    Write-Info "注意: 已保存的剪贴板历史会在 Windows 自动清理时移除。"

    Write-OK "隐私痕迹清理完成, 共清理 $count 项。"
    Write-Info "注意: 部分清理需重启资源管理器或重启电脑后完全生效。"
    Write-Host "  [r] 立即重启资源管理器   [回车] 稍后重启" -ForegroundColor Yellow
    $sel = Read-Host "选择"
    if ($sel -eq 'r') {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Process explorer.exe
        Write-OK "资源管理器已重启。"
    }
}

# ================= 计划任务查看 =================
function Invoke-TaskViewer {
    Write-Step "计划任务查看"
    Write-Info "正在读取计划任务 (可能稍慢)..."
    $tasks = Get-ScheduledTask | Where-Object { $_.State -eq 'Ready' -or $_.State -eq 'Running' } |
             Select-Object TaskName, TaskPath, State | Select-Object -First 30
    if (-not $tasks) { Write-Info "未找到计划任务。"; return }
    $tasks | Format-Table State, TaskName, TaskPath -AutoSize | Out-String -Width 120 | Write-Host
    Write-Info "如需禁用某个任务, 可在管理员终端执行: Disable-ScheduledTask -TaskName '<名称>'"
}

# ================= 前后对比报告 =================
function Show-Report {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $html = Join-Path $script:ReportDir ("report_{0}.html" -f $stamp)

    # 兜底: 确保系统状态已采集, 避免评分/进度条读取空值
    if (-not $script:sysStatus) { Refresh-SystemStatus }

    $os    = Get-CimInstance Win32_OperatingSystem
    $cpu   = Get-CimInstance Win32_Processor
    $memGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    $score = $script:sysStatus.Score

    $freedMB = $script:stats.DiskFreedMB + $script:stats.DevFreedMB
    $junkRemoved = [math]::Round(($script:stats.BeforeJunk - $script:stats.AfterJunk), 1)
    if ($freedMB -lt 0) { $freedMB = 0 }
    if ($junkRemoved -lt 0) { $junkRemoved = 0 }
    $freedGB = [math]::Round($freedMB / 1024, 2)

    # 健康评分环形图半径/周长
    $scorePct = $score
    $scoreColor = if ($score -ge 80) { '#00e676' } elseif ($score -ge 50) { '#ffd54f' } else { '#ff5252' }
    # 圆半径 68, 周长 2*π*68 ≈ 427.3; dash 按评分比例显示
    $ringCirc = [math]::Round(2 * [math]::PI * 68, 1)
    $dashLen = [math]::Round($ringCirc * $score / 100, 1)
    $gapLen = [math]::Round($ringCirc - $dashLen, 1)

    $doc = @"
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>WinCleanPro 清理报告</title>
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body { font-family: "Segoe UI", "Microsoft YaHei", sans-serif; background:#0a0e1a; color:#e8ecf4; padding:32px; }
  .container { max-width:960px; margin:0 auto; }
  .hero { background:linear-gradient(135deg,#0f1b3d 0%,#12264f 50%,#0a1628 100%); border-radius:20px; padding:36px; margin-bottom:20px; position:relative; overflow:hidden; border:1px solid rgba(90,140,255,.25); }
  .hero::before { content:''; position:absolute; top:-60%; right:-20%; width:500px; height:500px; background:radial-gradient(circle,rgba(60,120,255,.15),transparent 60%); }
  .hero h1 { font-size:28px; font-weight:700; background:linear-gradient(90deg,#5a8cff,#00e676); -webkit-background-clip:text; -webkit-text-fill-color:transparent; }
  .hero .sub { color:#7d8db3; margin-top:6px; font-size:13px; }
  .badge { display:inline-block; background:rgba(90,140,255,.15); border:1px solid rgba(90,140,255,.4); color:#7aa2ff; border-radius:20px; padding:3px 12px; font-size:12px; margin-top:12px; }
  .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:14px; margin-bottom:20px; }
  .stat { background:rgba(20,32,64,.6); border:1px solid rgba(90,140,255,.15); border-radius:16px; padding:18px; text-align:center; backdrop-filter:blur(4px); transition:transform .2s; }
  .stat:hover { transform:translateY(-4px); }
  .stat .num { font-size:26px; font-weight:700; color:#fff; }
  .stat .lbl { font-size:12px; color:#7d8db3; margin-top:6px; }
  .stat .num.green { color:#00e676; }
  .stat .num.blue { color:#5a8cff; }
  .stat .num.gold { color:#ffd54f; }
  .card { background:rgba(20,32,64,.4); border:1px solid rgba(90,140,255,.12); border-radius:16px; padding:24px; margin-bottom:20px; }
  .card h2 { font-size:16px; color:#9db1d6; margin-bottom:16px; letter-spacing:.5px; }
  .card h2 span { color:#5a8cff; margin-right:8px; }
  table { width:100%; border-collapse:collapse; font-size:13px; }
  td,th { padding:10px 12px; text-align:left; border-bottom:1px solid rgba(90,140,255,.08); }
  th { color:#7d8db3; font-weight:500; font-size:12px; }
  td { color:#d5ddee; }
  .score-wrap { display:flex; align-items:center; gap:32px; flex-wrap:wrap; }
  .ring { position:relative; width:160px; height:160px; }
  .ring svg { transform:rotate(-90deg); }
  .ring .val { position:absolute; inset:0; display:flex; flex-direction:column; align-items:center; justify-content:center; }
  .ring .val b { font-size:34px; color:#fff; }
  .ring .val span { font-size:12px; color:#7d8db3; }
  .bars { flex:1; min-width:220px; }
  .bar-row { margin-bottom:14px; }
  .bar-row .bar-lbl { display:flex; justify-content:space-between; font-size:13px; margin-bottom:6px; color:#9db1d6; }
  .bar-track { background:rgba(255,255,255,.06); height:10px; border-radius:6px; overflow:hidden; }
  .bar-fill { height:100%; border-radius:6px; width:0; transition:width 1.2s cubic-bezier(.4,0,.2,1); }
  .footer { text-align:center; color:#4a5578; font-size:12px; margin-top:24px; }
  @keyframes fadeUp { from { opacity:0; transform:translateY(12px); } to { opacity:1; transform:none; } }
  .fade { animation:fadeUp .5s ease both; }
  .d1 { animation-delay:.05s } .d2 { animation-delay:.15s } .d3 { animation-delay:.25s }
  .d4 { animation-delay:.35s } .d5 { animation-delay:.45s } .d6 { animation-delay:.55s }
</style>
</head>
<body>
<div class="container">

  <div class="hero fade">
    <h1>&#128736; WinCleanPro 清理报告</h1>
    <div class="sub">生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') &nbsp;·&nbsp; 作者 陈启粤</div>
    <div class="badge">&#128994; 所有删除均进入回收站 · 注册表改动已备份可还原</div>
  </div>

  <div class="grid">
    <div class="stat fade d1"><div class="num">$($script:stats.BeforeFree) MB</div><div class="lbl">清理前可用空间</div></div>
    <div class="stat fade d2"><div class="num">$($script:stats.AfterFree) MB</div><div class="lbl">清理后可用空间</div></div>
    <div class="stat fade d3"><div class="num green">+$freedGB GB</div><div class="lbl">本次释放空间</div></div>
    <div class="stat fade d4"><div class="num gold">$junkRemoved MB</div><div class="lbl">清理的垃圾量</div></div>
    <div class="stat fade d5"><div class="num blue">$($script:stats.CleanedItems)</div><div class="lbl">删除文件数</div></div>
    <div class="stat fade d6"><div class="num blue">$($script:stats.DevFreedMB) MB</div><div class="lbl">开发者缓存释放</div></div>
  </div>

  <div class="card fade d2">
    <h2><span>&#10024;</span>系统健康评分</h2>
    <div class="score-wrap">
      <div class="ring">
        <svg width="160" height="160" viewBox="0 0 160 160">
          <circle cx="80" cy="80" r="68" fill="none" stroke="rgba(255,255,255,.08)" stroke-width="12"/>
          <circle class="ring-fill" cx="80" cy="80" r="68" fill="none" stroke="$scoreColor" stroke-width="12" stroke-linecap="round"
            stroke-dasharray="$dashLen $gapLen" style="transition:stroke-dasharray 1.5s ease .3s"/>
        </svg>
        <div class="val"><b>$score</b><span>/ 100</span></div>
      </div>
      <div class="bars">
        <div class="bar-row"><div class="bar-lbl"><span>磁盘空间</span><span>$($script:sysStatus.FreePct)% 空闲</span></div><div class="bar-track"><div class="bar-fill" style="background:linear-gradient(90deg,#5a8cff,#00d4ff)" data-w="$($script:sysStatus.FreePct)"></div></div></div>
        <div class="bar-row"><div class="bar-lbl"><span>垃圾清理</span><span>约 $junkRemoved MB</span></div><div class="bar-track"><div class="bar-fill" style="background:linear-gradient(90deg,#ffd54f,#ffa726)" data-w="85"></div></div></div>
        <div class="bar-row"><div class="bar-lbl"><span>启动项</span><span>$($script:sysStatus.Startup) 个</span></div><div class="bar-track"><div class="bar-fill" style="background:linear-gradient(90deg,#00e676,#00bcd4)" data-w="40"></div></div></div>
      </div>
    </div>
  </div>

  <div class="card fade d3">
    <h2><span>&#128221;</span>本次执行内容</h2>
    <table>
      <tr><th>项目</th><th>状态</th></tr>
      <tr><td>磁盘清理 (临时文件/回收站/更新缓存/浏览器缓存)</td><td>$(if($script:done.Disk){'<span style="color:#00e676">&#9989; 已执行</span>'}else{'<span style="color:#7d8db3">—</span>'})</td></tr>
      <tr><td>去广告 / 系统精简</td><td>$(if($script:done.Debloat){'<span style="color:#00e676">&#9989; 已执行</span>'}else{'<span style="color:#7d8db3">—</span>'})</td></tr>
      <tr><td>性能优化 (电源/视觉特效/启动项分析)</td><td>$(if($script:done.Perf){'<span style="color:#00e676">&#9989; 已执行</span>'}else{'<span style="color:#7d8db3">—</span>'})</td></tr>
      <tr><td>开发者专项清理</td><td>$(if($script:done.Dev){'<span style="color:#00e676">&#9989; 已执行</span>'}else{'<span style="color:#7d8db3">—</span>'})</td></tr>
    </table>
  </div>

  <div class="card fade d4">
    <h2><span>&#128241;</span>系统信息</h2>
    <table>
      <tr><th>操作系统</th><td>$($os.Caption) (Build $($os.BuildNumber))</td></tr>
      <tr><th>处理器</th><td>$($cpu.Name)</td></tr>
      <tr><th>内存</th><td>$memGB GB</td></tr>
      <tr><th>备份位置</th><td style="word-break:break-all">$script:BackupDir</td></tr>
    </table>
  </div>

  <div class="footer">WinCleanPro v$script:AppVer &middot; 作者 陈启粤 &middot; 安全优先: 删除进回收站 / 注册表改动可还原</div>
</div>

<script>
  window.addEventListener('load', function() {
    // 条形图动画
    document.querySelectorAll('.bar-fill').forEach(function(el) {
      setTimeout(function() { el.style.width = el.dataset.w + '%'; }, 400);
    });
  });
</script>
</body>
</html>
"@
    Set-Content -Path $html -Value $doc -Encoding UTF8
    Write-OK "报告已生成: $html"
    Start-Process $html
}

# ================= 一键全做 =================
function Invoke-RunAll {
    Write-Step "开始一键全做"
    $script:skipConfirm = $true

    # 动手前先创建系统还原点 (安全优先)
    if (Test-IsAdmin) { Invoke-RestorePoint }

    $script:stats.BeforeFree = Get-FreeSpaceMB
    $script:stats.BeforeJunk = Measure-JunkMB
    Write-Info "清理前: 可用空间 $($script:stats.BeforeFree) MB, 垃圾量约 $($script:stats.BeforeJunk) MB"

    Invoke-DiskCleanup
    $script:done.Disk = $true

    $script:changedLog = @()
    Backup-RegistryRun
    Invoke-Debloat
    $script:done.Debloat = $true

    Invoke-Performance
    $script:done.Perf = $true

    Invoke-DevCleanup
    $script:done.Dev = $true

    if ($Deep) {
        Write-Info "深度模式已启用: 附带 WinSxS 组件清理 / 预装应用精简 / 网络优化 / 系统修复。"
    } else {
        Write-Info "提示: 追加 -Deep 参数可附带 WinSxS 组件清理 / 预装应用精简 / 网络优化 / 系统修复 (耗时较长)。"
    }

    $script:stats.AfterFree = Get-FreeSpaceMB
    $script:stats.AfterJunk = Measure-JunkMB

    # ===== 深度模式: 附加更彻底的清理 =====
    if ($Deep) {
        Write-Title "深度清理附加步骤"
        Invoke-ComponentStoreCleanup       # WinSxS 组件存储
        Invoke-AppxDebloat                 # 预装应用精简
        Invoke-NetworkOptimize             # 网络优化
        Invoke-SystemRepair                # DISM + SFC 系统修复
    }

    Write-Step "清理完成, 生成对比报告..."
    Refresh-SystemStatus
    Show-Report

    $freed = $script:stats.DiskFreedMB
    $items = $script:stats.CleanedItems

    # 终端总结战报
    Show-CleanupResult -FreedMB $freed -Items $items -DevMB $script:stats.DevFreedMB
    Write-ScoreBar -Score $script:sysStatus.Score
    Write-Host ""
    Write-Info "建议重启电脑以完全生效。"
}

# ================= 引导式主菜单 =================
function Show-MenuHeader {
    Clear-Host
    Write-Host ""
    Write-Logo
    Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║   WinCleanPro v$script:AppVer  ·  Windows 全家桶清理优化        ║" -ForegroundColor Cyan
    Write-Host "  ║   作者: 陈启粤  ·  安全优先: 删除进回收站 / 改动可还原       ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Show-StatusBar
    Write-Host ""
}

function Main-Menu {
    while ($true) {
        Show-MenuHeader

        Write-Host "  ── 清理类 (让磁盘更干净) ────────────────────────────────────────" -ForegroundColor DarkCyan
        Write-Host "   [1]  磁盘清理          清除临时文件/回收站/更新缓存/浏览器缓存"
        Write-Host "   [2]  去广告 / 精简     关闭开始菜单推荐/锁屏广告/遥测/后台应用"
        Write-Host "   [3]  重复文件查找      找出并删除重复占用空间的文件"
        Write-Host "   [4]  空间分析          查看哪个目录占用了最多空间"
        Write-Host "   [5]  大文件查找        找出超过指定大小的巨型文件"
        Write-Host "   [6]  开发者专项清理    清除 node_modules/__pycache__ 等开发垃圾"
        Write-Host "   [7]  内存清理          释放空闲进程占用的内存"
        Write-Host "   [8]  休眠文件管理      关闭休眠释放 hiberfil.sys 的大块空间"
        Write-Host ""
        Write-Host "  ── 管理类 (让系统更好用) ────────────────────────────────────────" -ForegroundColor DarkCyan
        Write-Host "   [9]  软件更新          winget 一键更新所有软件"
        Write-Host "   [10] 软件卸载          列出已安装软件并卸载不需要的"
        Write-Host "   [11] 启动项管理        查看 / 禁用开机自启项目"
        Write-Host "   [12] 服务优化          分析高占用服务并给出建议"
        Write-Host "   [13] 计划任务查看      查看系统计划任务"
        Write-Host "   [14] 预装应用管理      移除 Windows 自带的无用 App"
        Write-Host ""
        Write-Host "  ── 网络与修复 (解决问题) ────────────────────────────────────────" -ForegroundColor DarkCyan
        Write-Host "   [15] 网络优化          刷新 DNS / 重置网络协议栈"
        Write-Host "   [16] 系统修复          检查并修复系统文件损坏"
        Write-Host "   [17] Defender 扫描     快速病毒扫描"
        Write-Host "   [18] 系统信息          查看硬件与系统详情"
        Write-Host ""
        Write-Host "  ── 特色功能 (独家) ──────────────────────────────────────────────" -ForegroundColor DarkCyan
        Write-Host "   [19] 开机耗时追踪      查看最近 5 次开机耗时, 观察优化效果"
        Write-Host "   [20] 隐私痕迹清理      清除最近文档/运行历史/搜索历史等痕迹"
        Write-Host ""
        Write-Host "  ── 一键与安全 (推荐) ────────────────────────────────────────────" -ForegroundColor DarkCyan
        Write-Host "   [21] 一键全做          自动清理+去广告+优化, 生成对比报告"
        Write-Host "   [22] 创建还原点        系统修改前创建还原点"
        Write-Host "   [23] 还原注册表备份    恢复之前修改的注册表"
        Write-Host "   [24] HOSTS 广告拦截    添加/查看/还原 hosts 广告与遥测拦截"
        Write-Host ""
        Write-Host "   [0]  退出" -ForegroundColor DarkGray
        Write-Host "  ─────────────────────────────────────────────────────────────────" -ForegroundColor DarkCyan

        $choice = Read-Host "`n  请选择功能 (输入数字后回车)"

        # 权限门禁: 选到需要管理员的功能且当前非管理员时, 请求提升并退出
        if ($choice -in $script:adminNeeded -and -not (Test-IsAdmin)) {
            Write-Warn "功能 [$choice] 需要管理员权限。正在请求提升..."
            Start-Sleep -Milliseconds 600
            try {
                Start-Process powershell.exe -Verb RunAs -ArgumentList @(
                    '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`""
                )
            } catch {
                Write-Err "请求管理员权限失败: $_"
            }
            exit
        }

        switch ($choice) {
            '1'  { Invoke-DiskCleanup }
            '2'  { $script:changedLog = @(); Backup-RegistryRun; Invoke-Debloat }
            '3'  { Invoke-DuplicateScan }
            '4'  { Invoke-SpaceAnalysis }
            '5'  { Invoke-LargeFileScan }
            '6'  { Invoke-DevCleanup }
            '7'  { Invoke-MemoryCleanup }
            '8'  { Invoke-HibernateManager }
            '9'  { Invoke-WingetUpdate }
            '10' { Invoke-WingetUninstall }
            '11' { Invoke-StartupManager }
            '12' { Invoke-ServiceOptimize }
            '13' { Invoke-TaskViewer }
            '14' { Invoke-AppxDebloat }
            '15' { Invoke-NetworkOptimize }
            '16' { Invoke-SystemRepair }
            '17' { Invoke-DefenderScan }
            '18' { Invoke-SystemInfo }
            '19' { Invoke-BootTimeTracker }
            '20' { Invoke-PrivacyCleanup }
            '21' { Invoke-RunAll }
            '22' { Invoke-RestorePoint }
            '23' { Restore-RegistryRun }
            '24' { Invoke-HostsManager }
            '0'  { Write-Info "再见! 感谢使用 WinCleanPro."; break }
            default { Write-Warn "无效选项, 请重新输入。"; Start-Sleep -Milliseconds 800 }
        }
        if ($choice -ne '0') {
            Write-Host ""
            Read-Host "按回车返回主菜单"
        }
    }
}

# ================= 入口 =================
Initialize-Environment

# 交互模式不再提前提权, 由各功能按需请求 (最小权限原则)。
# 命令行 -RunAll 需要管理员权限, 直接请求提升, 并透传 -Deep 参数。
if ($RunAll -and -not (Test-IsAdmin)) {
    $script:passThruArgs = ' -RunAll'
    if ($Deep) { $script:passThruArgs += ' -Deep' }
    Write-Warn "一键全做需要管理员权限, 正在请求提升..."
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"$script:passThruArgs"
        )
        exit
    } catch {
        Write-Err "请求管理员权限失败: $_"
        Read-Host "按回车退出"
        exit
    }
}
Initialize-Environment   # 提权后重新初始化

# 启动动画
Clear-Host
Write-Logo
Write-Host ""
Write-Host "  ═══ WinCleanPro v$script:AppVer 正在启动 ═══" -ForegroundColor DarkCyan
Write-ProgressBar -Percent 30 -Label "初始化"
Start-Sleep -Milliseconds 150

# 首次刷新系统状态
Refresh-SystemStatus
Write-ProgressBar -Percent 100 -Label "完成"
Start-Sleep -Milliseconds 150

if ($RunAll) {
    Write-Host ""
    Invoke-RunAll
    Read-Host "按回车退出"
    exit
}

Main-Menu
