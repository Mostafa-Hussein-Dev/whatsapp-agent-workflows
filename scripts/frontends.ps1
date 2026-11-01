<#
Restarts the two Next.js dev servers (admin dashboard 3100, business portal 3200) in one of two modes.

  .\scripts\frontends.ps1 -Mode ngrok   pages call the API through their own /backend path, so ONE ngrok tunnel per site is enough
  .\scripts\frontends.ps1 -Mode local   normal setup: pages call http://localhost:8000 directly (use this when you are done with ngrok)

Only the processes listening on ports 3100 and 3200 are stopped. The API, n8n and port 3000 are not touched.
#>
param([ValidateSet('ngrok', 'local')][string]$Mode = 'local')

$root = Split-Path -Parent $PSScriptRoot

foreach ($port in 3100, 3200) {
    $c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { Stop-Process -Id $c.OwningProcess -Force }
}
Start-Sleep -Seconds 2

if ($Mode -eq 'ngrok') {
    $env:NEXT_PUBLIC_API_URL = '/backend'
    $env:API_PROXY_TARGET = 'http://localhost:8000'
    $env:PORTAL_PROXY_TARGET = 'http://localhost:3200'
    $env:PORTAL_BASE_PATH = '/portal'
} else {
    foreach ($name in 'NEXT_PUBLIC_API_URL', 'API_PROXY_TARGET', 'PORTAL_PROXY_TARGET', 'PORTAL_BASE_PATH') {
        Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    }
}

Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', 'npx next dev -p 3100' -WorkingDirectory (Join-Path $root 'admin-dashboard') -WindowStyle Hidden
Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', 'npx next dev -p 3200' -WorkingDirectory (Join-Path $root 'business-portal') -WindowStyle Hidden
Write-Host "Frontends restarted in '$Mode' mode (admin 3100, portal 3200). Give them ~15 seconds."
