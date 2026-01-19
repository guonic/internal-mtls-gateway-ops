<#
.SYNOPSIS
从.env文件读取配置，检测公网IP与域名解析一致性，自动调用URL更新DNS
.DESCRIPTION
兼容Shell格式的.env文件（支持export前缀），无需硬编码配置，适合动态公网IP场景
#>

# -------------------------- 核心函数：导入.env文件 --------------------------
function Import-EnvFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    # 校验.env文件是否存在
    if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
        Write-Host "[$(Get-Date)] ERROR: .env文件不存在 - $FilePath" -ForegroundColor Red
        return $null
    }

    $envVars = @{}
    # 逐行读取并解析.env文件
    Get-Content -Path $FilePath | ForEach-Object {
        $line = $_.Trim()
        # 跳过注释行和空行
        if (-not $line -or $line.StartsWith('#')) { return }
        # 移除export前缀（兼容Shell格式）
        $line = $line -replace "^export\s+", ""
        # 分割键值对（仅分割第一个=，避免值中包含=）
        $keyValue = $line -split '=', 2
        if ($keyValue.Length -eq 2) {
            $key = $keyValue[0].Trim()
            $value = $keyValue[1].Trim()
            # 去除值两侧的引号（处理带引号的配置，如 VALUE="xxx"）
            $value = $value -replace '^(["''])|(["''])$', ''
            $envVars[$key] = $value
            # 加载为当前PowerShell会话的环境变量
            [Environment]::SetEnvironmentVariable($key, $value, "Process")
        }
    }

    return $envVars
}

# -------------------------- 工具函数：获取公网IP --------------------------
function Get-PublicIp {
    param(
        [int]$Timeout = 10
    )
    try {
        # 调用公网IP检测接口，可替换为ifconfig.me/ipinfo.io/ip等
        $response = Invoke-RestMethod -Uri "https://ipinfo.io" -Method Get -TimeoutSec $Timeout
        $publicIp = $response.Trim()
        # 验证是否为合法IPv4地址
        if ($publicIp -match "\b(?:\d{1,3}\.){3}\d{1,3}\b") {
            return $publicIp
        }
        else {
            Write-Host "[$(Get-Date)] ERROR: 获取的公网IP格式非法 - $publicIp" -ForegroundColor Red
            return $null
        }
    }
    catch {
        Write-Host "[$(Get-Date)] ERROR: 获取公网IP失败 - $_" -ForegroundColor Red
        return $null
    }
}

# -------------------------- 工具函数：解析域名DNS IP --------------------------
function Get-DomainIp {
    param(
        [string]$Domain,
        [string]$DnsServer = "8.8.8.8",
        [int]$Timeout = 10
    )
    try {
        # 使用指定DNS服务器解析A记录
        $dnsResult = Resolve-DnsName -Name $Domain -Server $DnsServer -Type A -Timeout $Timeout -ErrorAction Stop
        return $dnsResult.IPAddress[0]
    }
    catch {
        Write-Host "[$(Get-Date)] ERROR: 解析域名 $Domain 失败 - $_" -ForegroundColor Red
        return $null
    }
}

# -------------------------- 主程序执行逻辑 --------------------------
# 1. 导入.env配置（请修改为你的.env文件实际路径）
$envConfig = Import-EnvFile -FilePath ".env"
if ($null -eq $envConfig) {
    exit 1
}

# 2. 读取配置参数（从.env加载的环境变量）
$domain = $env:PRIVATE_DOMAIN
$updateUrl = $env:DNS_REGISTER
$token=$env:UPDATE_DNS_TOKEN

# 3. 校验必要配置
if (-not $domain -or -not $updateUrl) {
    Write-Host "[$(Get-Date)] ERROR: .env文件中必须配置 PRIVATE_DOMAIN 和 DNS_REGISTER" -ForegroundColor Red
    exit 1
}

# 4. 获取公网IP和域名解析IP
$publicIp = Get-PublicIp -Timeout 5
$domainIp = Get-DomainIp -Domain $domain -DnsServer "8.8.8.8" -Timeout 5

if ($null -eq $publicIp -or $null -eq $domainIp) {
    Write-Host "[$(Get-Date)] ERROR: IP获取失败，退出程序" -ForegroundColor Red
    exit 1
}

# 5. 对比IP并更新DNS
Write-Host "[$(Get-Date)] INFO: 域名 $domain 解析IP: $domainIp | 本地公网IP: $publicIp" -ForegroundColor Cyan
if ($publicIp -ne $domainIp) {
    Write-Host "[$(Get-Date)] INFO: IP不一致，开始更新DNS..." -ForegroundColor Yellow
    # 替换更新URL中的{IP}占位符
    $finalUpdateUrl = "$updateUrl?ipv4=auto&token=$token&zone=$domain"
    try {
        $updateResponse = Invoke-RestMethod -Uri $finalUpdateUrl -Method Get -TimeoutSec 5
        Write-Host "[$(Get-Date)] SUCCESS: DNS更新成功，接口返回: $($updateResponse | ConvertTo-Json)" -ForegroundColor Green
    }
    catch {
        Write-Host "[$(Get-Date)] ERROR: DNS更新失败 - $_" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "[$(Get-Date)] INFO: IP一致，无需更新DNS" -ForegroundColor Gray
}

# 程序正常退出
exit 0