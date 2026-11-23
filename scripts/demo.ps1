[CmdletBinding()]
param(
    [switch] $SkipBuild,
    [ValidateRange(1, 65535)]
    [int] $Port = 7357
)

$ErrorActionPreference = 'Stop'
$services = @('postgres', 'ai-engine', 'backend', 'catalog-seed')
$secretValues = @()

function Invoke-DemoDocker {
    param([string[]] $Arguments, [switch] $Stream)

    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    if ($Stream) {
        & docker @Arguments 2>&1 | ForEach-Object {
            $line = $_.ToString()
            foreach ($secret in $secretValues) {
                $line = $line.Replace($secret, '[ẩn]')
            }
            Write-Host $line
        }
        return $LASTEXITCODE
    }

    $lines = & docker @Arguments 2>&1
    [pscustomobject] @{
        ExitCode = $LASTEXITCODE
        Lines = @($lines | ForEach-Object { $_.ToString() })
    }
}

function Show-DemoDiagnostics {
    param([string[]] $FailedServices = $services)

    Write-Host 'Trạng thái container:'
    $null = Invoke-DemoDocker -Arguments (@('compose', 'ps', '-a') + $services) -Stream
    Write-Host '30 dòng log cuối của mỗi dịch vụ cần kiểm tra:'
    $null = Invoke-DemoDocker -Arguments (@('compose', 'logs', '--no-color', '--tail=30') + $FailedServices) -Stream
}

Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    foreach ($command in @('docker', 'flutter')) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            throw "Không tìm thấy '$command' trong PATH. Cài công cụ và mở lại PowerShell."
        }
    }
    if ((Invoke-DemoDocker -Arguments @('compose', 'version')).ExitCode -ne 0) {
        throw 'Không chạy được Docker Compose. Kiểm tra lại bản cài Docker Desktop.'
    }
    if ((Invoke-DemoDocker -Arguments @('info', '--format', '{{.ServerVersion}}')).ExitCode -ne 0) {
        throw 'Docker Engine chưa chạy hoặc không kết nối được. Mở Docker Desktop, chờ Engine sẵn sàng rồi chạy lại.'
    }
    if (-not (Test-Path -LiteralPath '.env' -PathType Leaf)) {
        throw 'Thiếu .env. Chạy python scripts/make_demo_env.py ở thư mục gốc để tạo file rồi thử lại.'
    }
    if (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue) {
        throw "Cổng Flutter $Port đang được dùng. Hãy dừng tiến trình đó hoặc chạy lại với -Port khác, ví dụ -Port 7358."
    }

    # Compose đọc .env và các cấu hình override. Chỉ dùng kết quả trong bộ nhớ.
    $rendered = Invoke-DemoDocker -Arguments @('compose', 'config', '--format', 'json')
    if ($rendered.ExitCode -ne 0) {
        throw 'Cấu hình Compose không hợp lệ. Kiểm tra .env và các biến bắt buộc trong .env.example.'
    }
    try {
        $config = ($rendered.Lines -join "`n") | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw 'Không đọc được cấu hình JSON từ Docker Compose. Hãy kiểm tra phiên bản Compose và cấu hình local.'
    }
    foreach ($item in $config.services.PSObject.Properties) {
        $environment = $item.Value.environment
        if ($environment) {
            $secretValues += @($environment.PSObject.Properties |
                Where-Object { $_.Name -match 'PASSWORD|SECRET|TOKEN|DATABASE_URL' -and $_.Value } |
                ForEach-Object { [string] $_.Value })
        }
    }
    $targets = @($config.services.backend.ports | ForEach-Object { $_.target } | Where-Object { $_ } | Select-Object -Unique)
    if ($targets.Count -ne 1) {
        throw 'Cần đúng một cổng nội bộ được công bố cho backend trong cấu hình Compose.'
    }

    $up = @('compose', '--progress', 'plain', 'up', '-d', '--wait', '--wait-timeout', '180')
    if (-not $SkipBuild) { $up += '--build' }
    Write-Host 'Khởi động PostgreSQL, AI Engine, backend và nạp catalog. Đợi dịch vụ sẵn sàng tối đa 180 giây sau khi build...'
    if ((Invoke-DemoDocker -Arguments ($up + $services) -Stream) -ne 0) {
        Show-DemoDiagnostics
        throw 'Compose không khởi động được đầy đủ dịch vụ hoặc đã hết thời gian chờ.'
    }

    $status = Invoke-DemoDocker -Arguments (@('compose', 'ps', '-a', '--format', 'json') + $services)
    $containers = @()
    if ($status.ExitCode -eq 0) {
        $jsonLines = ($status.Lines -join "`n").Trim()
        if ($jsonLines.StartsWith('[')) {
            $containers = @($jsonLines | ConvertFrom-Json)
        } else {
            $containers = @($status.Lines | Where-Object { $_.Trim().StartsWith('{') } |
                ForEach-Object { $_ | ConvertFrom-Json })
        }
    }
    $failed = @()
    foreach ($service in @('postgres', 'ai-engine', 'backend')) {
        $rows = @($containers | Where-Object Service -eq $service)
        if ($rows.Count -ne 1 -or $rows[0].State -ne 'running' -or $rows[0].Health -ne 'healthy') {
            $failed += $service
        }
    }
    $seed = @($containers | Where-Object Service -eq 'catalog-seed')
    if ($seed.Count -ne 1 -or $seed[0].State -ne 'exited' -or "$($seed[0].ExitCode)" -ne '0') {
        $failed += 'catalog-seed'
    }
    if ($failed.Count) {
        Show-DemoDiagnostics -FailedServices $failed
        throw "Dịch vụ chưa sẵn sàng: $($failed -join ', ')."
    }
    Write-Host 'PostgreSQL, AI Engine và backend đã healthy. Catalog đã nạp xong (mã thoát 0).'

    $binding = Invoke-DemoDocker -Arguments @('compose', 'port', 'backend', [string] $targets[0])
    $hostPorts = @($binding.Lines | ForEach-Object {
        if ($_ -match ':(\d+)\s*$') { $Matches[1] }
    } | Select-Object -Unique)
    if ($binding.ExitCode -ne 0 -or $hostPorts.Count -ne 1) {
        Show-DemoDiagnostics -FailedServices @('backend')
        throw 'Không xác định được cổng backend từ docker compose port.'
    }
    $apiBase = "http://localhost:$($hostPorts[0])"
    try {
        $response = Invoke-WebRequest -Uri "$apiBase/" -UseBasicParsing -TimeoutSec 10
        if ($response.StatusCode -ne 200) { throw 'Backend chưa trả HTTP 200.' }
    } catch {
        Show-DemoDiagnostics -FailedServices @('backend')
        throw "Backend không trả HTTP 200 khi gọi GET $apiBase/."
    }

    Write-Host "Backend: $apiBase (GET / trả HTTP 200)"
    Write-Host "Mở trình duyệt: http://localhost:$Port"
    Write-Host 'Tài khoản demo: user1@sharegrid.vn, host1@sharegrid.vn, admin@sharegrid.vn'
    Write-Host 'Nút demo điền email. Nhập mật khẩu của tài khoản trên màn hình đăng nhập.'
    & flutter run -d chrome --web-hostname localhost --web-port $Port --no-web-resources-cdn "--dart-define=API_BASE_URL=$apiBase" --dart-define=DEMO_OFFLINE=true
    if ($LASTEXITCODE -ne 0) { throw "Flutter thoát với mã $LASTEXITCODE. Kiểm tra Chrome và thông báo phía trên." }
} catch {
    Write-Host "Lỗi demo: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    Pop-Location
}
