[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Không tìm thấy Docker trong PATH.'
    }
    & docker compose stop postgres ai-engine backend catalog-seed
    if ($LASTEXITCODE -ne 0) { throw 'Không dừng được stack demo. Kiểm tra Docker Desktop và cấu hình .env.' }
    Write-Host 'Đã dừng các dịch vụ demo. Volume PostgreSQL vẫn được giữ.'
    Write-Host 'Nhấn q trong cửa sổ Flutter để dừng giao diện. Chạy lại bằng .\scripts\demo.ps1.'
} catch {
    Write-Host "Lỗi dừng demo: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    Pop-Location
}
