# Laf for Windows setup. Run from this folder, as your normal user (not as administrator):
#   powershell -ExecutionPolicy Bypass -File .\setup.ps1
# Safe to re-run: it updates the app and keeps your settings and words.
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # Invoke-WebRequest is very slow with the progress bar

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$app = Join-Path $env:LOCALAPPDATA "Laf"
$cfgDir = Join-Path $env:APPDATA "Laf"
New-Item -ItemType Directory -Force $app, "$app\models", "$app\whisper", $cfgDir | Out-Null

Write-Host "1/5 uv"
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
    $env:Path = "$env:USERPROFILE\.local\bin;$env:Path"
}

Write-Host "2/5 Python environment"
Get-Process pythonw -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$app\*" } | Stop-Process -Force
Copy-Item "$here\laf.pyw" $app -Force
uv venv --python 3.12 --allow-existing "$app\.venv"
uv pip install --python "$app\.venv\Scripts\python.exe" -r "$here\requirements.txt"
if ($LASTEXITCODE -ne 0) { throw "uv pip install failed" }

Write-Host "3/5 whisper.cpp"
$gpu = [bool](Get-Command nvidia-smi -ErrorAction SilentlyContinue)
$asset = if ($gpu) { "whisper-cublas-12.4.0-bin-x64.zip" } else { "whisper-bin-x64.zip" }
if (-not (Test-Path "$app\whisper\whisper-server.exe")) {
    $releases = Invoke-RestMethod "https://api.github.com/repos/ggml-org/whisper.cpp/releases?per_page=30"
    $url = ($releases | ForEach-Object { $_.assets } | Where-Object { $_.name -eq $asset } | Select-Object -First 1).browser_download_url
    if (-not $url) { throw "Could not find $asset in the whisper.cpp releases" }
    Write-Host "   downloading $asset"
    $zip = Join-Path $env:TEMP "laf-whisper.zip"
    $tmp = Join-Path $env:TEMP "laf-whisper"
    Invoke-WebRequest $url -OutFile $zip
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Expand-Archive $zip $tmp -Force
    $server = Get-ChildItem $tmp -Recurse -Filter whisper-server.exe | Select-Object -First 1
    if (-not $server) { throw "whisper-server.exe not found in $asset" }
    Copy-Item "$($server.DirectoryName)\*" "$app\whisper" -Recurse -Force
    Remove-Item $zip, $tmp -Recurse -Force
}

Write-Host "4/5 speech model"
# With an NVIDIA GPU the larger, more accurate model is fast enough. On CPU, small.en keeps it to a second or two.
$model = if ($gpu) { "ggml-large-v3-turbo-q5_0.bin" } else { "ggml-small.en-q5_1.bin" }
if (-not (Test-Path "$app\models\$model")) {
    Write-Host "   downloading $model"
    Invoke-WebRequest "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$model" -OutFile "$app\models\$model.part"
    Move-Item "$app\models\$model.part" "$app\models\$model" -Force
}

Write-Host "5/5 settings"
$cfgPath = Join-Path $cfgDir "config.json"
if (-not (Test-Path $cfgPath)) {
    # Only machine-specific values; Laf fills in the defaults for everything else.
    $cfg = [ordered]@{
        whisperServer  = "$app\whisper\whisper-server.exe"
        whisperModel   = "$app\models\$model"
        whisperThreads = [Math]::Min(8, [Environment]::ProcessorCount)
    }
    [IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json))
}

Write-Host "`nSelf-test:"
& "$app\.venv\Scripts\python.exe" "$app\laf.pyw" --selftest
if ($LASTEXITCODE -ne 0) { throw "Self-test failed" }

Start-Process "$app\.venv\Scripts\pythonw.exe" -ArgumentList "`"$app\laf.pyw`""
Write-Host "`nLaf is running (tray icon). Hold Right Ctrl to dictate."
Write-Host "To turn on cleanup, choose 'Set API key...' in the tray menu."
Write-Host "Logs: $app\laf.log and $app\whisper.log  Settings: $cfgPath"
