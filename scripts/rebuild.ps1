# Rebuilds every seed, model and test with dbt.
# While the project stays on the BigQuery sandbox, tables expire 60 days after they
# are created. Running this every ~6 weeks re-creates them before that happens.
# The data window is fixed and the seed is the local CSV, so every rebuild
# reproduces the same figures.
#
# Run by hand:      .\scripts\rebuild.ps1
# Scheduled:        see "Keeping the sandbox tables alive" in the README.
# Cost:             one full dbt build, about 8 GiB of query quota.

$ErrorActionPreference = "Stop"
Set-Location -Path (Join-Path $PSScriptRoot "..")

if (-not (Test-Path "seeds\ofac_wallets.csv")) {
    throw "Missing seeds\ofac_wallets.csv. Run: python scripts\extract_wallets.py"
}

New-Item -ItemType Directory -Force -Path "logs" | Out-Null
$log = "logs\rebuild_$(Get-Date -Format yyyyMMdd_HHmm).log"

& ".\.venv\Scripts\dbt.exe" build *>&1 | Tee-Object -FilePath $log
if ($LASTEXITCODE -ne 0) {
    throw "dbt build failed. See $log"
}
Write-Output "dbt build finished. Log: $log"
