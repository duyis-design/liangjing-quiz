param(
  [string]$RepoName = "liangjing-quiz"
)

$ErrorActionPreference = "Stop"
Set-Location -Path (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Refresh-Path {
  $m = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $u = [Environment]::GetEnvironmentVariable("Path", "User")
  if ($m -or $u) { $env:Path = "$m;$u" }
}

function Missing($cmd) {
  return -not (Get-Command $cmd -ErrorAction SilentlyContinue)
}

Write-Host "=== Deploy quiz to GitHub Pages ===" -ForegroundColor Cyan

if (-not (Test-Path ".\index.html")) {
  Write-Host "index.html not found. Run this script inside the site folder." -ForegroundColor Red
  Read-Host "Press Enter to exit"
  exit 1
}

# 1. git
if (Missing git) {
  Write-Host "[1/6] Installing Git..." -ForegroundColor Yellow
  winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
  Refresh-Path
}
if (Missing git) {
  Write-Host "Git installation failed. Please install it from https://git-scm.com/download/win and run again." -ForegroundColor Red
  Read-Host "Press Enter to exit"
  exit 1
}

# 2. gh
if (Missing gh) {
  Write-Host "[2/6] Installing GitHub CLI..." -ForegroundColor Yellow
  winget install --id GitHub.cli -e --source winget --accept-package-agreements --accept-source-agreements
  Refresh-Path
}
if (Missing gh) {
  Write-Host "GitHub CLI installation failed. Download it from https://cli.github.com and run again." -ForegroundColor Red
  Read-Host "Press Enter to exit"
  exit 1
}

# 3. login
& gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host "[3/6] Sign in to GitHub. A browser window will open." -ForegroundColor Yellow
  Write-Host "      Paste the one-time code shown in the terminal, then authorize." -ForegroundColor Gray
  gh auth login --web --git-protocol https
}

$login = (gh api user --jq .login).Trim()
Write-Host "Signed in as: $login" -ForegroundColor Green

# 4. commit
if (-not (Test-Path ".git")) {
  git init -b main | Out-Null
}
git config user.name $login
git config user.email "$login@users.noreply.github.com"

git add -A
git commit -m "deploy quiz site" *> $null
Write-Host "[4/6] Local repository ready." -ForegroundColor Green

# 5. create repo and push
& gh repo view "$login/$RepoName" *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host "[5/6] Creating repository $RepoName ..." -ForegroundColor Yellow
  gh repo create $RepoName --public --source=. --remote=origin --push
} else {
  Write-Host "[5/6] Repository exists, pushing updates ..." -ForegroundColor Yellow
  & git remote get-url origin *> $null
  if ($LASTEXITCODE -ne 0) {
    git remote add origin "https://github.com/$login/$RepoName.git"
  }
  git push -u origin main
}

# 6. enable pages
Write-Host "[6/6] Enabling GitHub Pages ..." -ForegroundColor Yellow
& gh api "repos/$login/$RepoName/pages" *> $null
if ($LASTEXITCODE -ne 0) {
  gh api -X POST "repos/$login/$RepoName/pages" -f "source[branch]=main" -f "source[path]=/" | Out-Null
}

$url = "https://$login.github.io/$RepoName/"

Write-Host ""
Write-Host "Building... first deployment usually takes 1-3 minutes." -ForegroundColor Gray
for ($i = 0; $i -lt 20; $i++) {
  Start-Sleep -Seconds 6
  $status = (gh api "repos/$login/$RepoName/pages" --jq .status 2>$null)
  if ($status -eq "built") { break }
}

Write-Host ""
Write-Host "Your quiz is live at:" -ForegroundColor Green
Write-Host "  $url" -ForegroundColor Yellow
Write-Host ""
Write-Host "Tip: if it shows 404, wait one more minute and refresh." -ForegroundColor Gray
Start-Process $url
Read-Host "Press Enter to exit"
