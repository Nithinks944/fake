param(
    [Parameter(Mandatory = $false)]
    [string]$RepoPath = "."
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-PackageJsonHasTestScript {
    param([string]$Path)

    $packageJsonPath = Join-Path $Path "package.json"
    if (-not (Test-Path $packageJsonPath)) {
        return $false
    }

    try {
        $packageJson = Get-Content -Raw -Path $packageJsonPath | ConvertFrom-Json
    }
    catch {
        return $false
    }

    if ($null -eq $packageJson.scripts) {
        return $false
    }

    $testScript = $packageJson.scripts.test
    return -not [string]::IsNullOrWhiteSpace([string]$testScript)
}

function Test-HasPytestSignals {
    param([string]$Path)

    $pytestConfigFiles = @(
        "pytest.ini",
        "tox.ini"
    )

    foreach ($file in $pytestConfigFiles) {
        if (Test-Path (Join-Path $Path $file)) {
            return $true
        }
    }

    $pyprojectPath = Join-Path $Path "pyproject.toml"
    if (Test-Path $pyprojectPath) {
        $content = Get-Content -Raw -Path $pyprojectPath
        if ($content -match "\[tool\.pytest\.ini_options\]" -or $content -match "pytest") {
            return $true
        }
    }

    $requirementsFiles = @(
        "requirements.txt",
        "requirements-dev.txt"
    )

    foreach ($file in $requirementsFiles) {
        $fullPath = Join-Path $Path $file
        if (Test-Path $fullPath) {
            $content = Get-Content -Raw -Path $fullPath
            if ($content -match "(^|\s)pytest([<>=~!]|\s|$)") {
                return $true
            }
        }
    }

    return $false
}

function Test-HasGoTests {
    param([string]$Path)

    $goTests = @(Get-ChildItem -Path $Path -Recurse -File -Filter "*_test.go" -ErrorAction SilentlyContinue)
    return $goTests.Count -gt 0
}

function Test-HasLocalTestScript {
    param([string]$Path)

    $patterns = @(
        "test.ps1",
        "test.sh",
        "test.cmd",
        "test.bat",
        "run-tests.ps1",
        "run-tests.sh",
        "run-tests.cmd",
        "run-tests.bat"
    )

    foreach ($pattern in $patterns) {
        $matches = @(Get-ChildItem -Path $Path -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue)
        if ($matches.Count -gt 0) {
            return $true
        }
    }

    if (Test-Path (Join-Path $Path "scripts")) {
        $scriptMatches = @(Get-ChildItem -Path (Join-Path $Path "scripts") -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "(^test|test|run-tests)" }
        )
        if ($scriptMatches.Count -gt 0) {
            return $true
        }
    }

    return $false
}

$resolvedRepoPath = Resolve-Path -Path $RepoPath
$workflowsPath = Join-Path $resolvedRepoPath ".github/workflows"

$workflowFiles = @()
if (Test-Path $workflowsPath) {
    $workflowFiles = @(
        Get-ChildItem -Path $workflowsPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.yml', '.yaml') }
    )
}

$hasWorkflow = $workflowFiles.Count -gt 0
$hasLocalTestScript = Test-HasLocalTestScript -Path $resolvedRepoPath
$hasPackageJsonTestScript = Test-PackageJsonHasTestScript -Path $resolvedRepoPath
$hasPytest = Test-HasPytestSignals -Path $resolvedRepoPath
$hasGoTests = Test-HasGoTests -Path $resolvedRepoPath

if ($hasWorkflow -and -not $hasLocalTestScript -and -not $hasPackageJsonTestScript -and -not $hasPytest -and -not $hasGoTests) {
    Write-Host "Validation result: FAIL" -ForegroundColor Red
    Write-Host "Reason: GitHub workflow exists, but no local test execution path was found." -ForegroundColor Red
    Write-Host "Detected:" -ForegroundColor Yellow
    Write-Host "  - Workflow files: $($workflowFiles.Count)" -ForegroundColor Yellow
    Write-Host "  - Local test script: $hasLocalTestScript" -ForegroundColor Yellow
    Write-Host "  - package.json test script: $hasPackageJsonTestScript" -ForegroundColor Yellow
    Write-Host "  - pytest: $hasPytest" -ForegroundColor Yellow
    Write-Host "  - go test files: $hasGoTests" -ForegroundColor Yellow
    exit 1
}

Write-Host "Validation result: PASS" -ForegroundColor Green
Write-Host "Detected:" -ForegroundColor Cyan
Write-Host "  - Workflow files: $($workflowFiles.Count)" -ForegroundColor Cyan
Write-Host "  - Local test script: $hasLocalTestScript" -ForegroundColor Cyan
Write-Host "  - package.json test script: $hasPackageJsonTestScript" -ForegroundColor Cyan
Write-Host "  - pytest: $hasPytest" -ForegroundColor Cyan
Write-Host "  - go test files: $hasGoTests" -ForegroundColor Cyan
exit 0
