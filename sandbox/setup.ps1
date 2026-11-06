# Installs the admin tools inside Windows Sandbox, then checks the session.
# Runs at sign-in from v1be-admin.wsb. The Sandbox is thrown away on close, so
# this runs every time.
#
# Every download is pinned and checked against a SHA-256 hash. To update a tool,
# change its version and hash together. Hashes come from each publisher:
#   Terraform  releases.hashicorp.com/terraform/<version>/ SHA256SUMS
#   gh         the release's checksums.txt
#   Git        the release notes
#   AWS CLI    no published hash, so hash the MSI yourself and confirm that its
#              Authenticode signer is Amazon Web Services, Inc.

$ErrorActionPreference = 'Stop'

$terraformVersion = '1.17.1'
$awsVersion = '2.39.4'
$ghVersion = '2.103.3'
$gitVersion = '2.56.0.4'
$gitTag = 'v2.56.0.windows.4'

$downloads = @(
    @{
        Name = 'Terraform'
        File = "terraform_${terraformVersion}_windows_amd64.zip"
        Url  = "https://releases.hashicorp.com/terraform/$terraformVersion/terraform_${terraformVersion}_windows_amd64.zip"
        Hash = 'a3b71365cff94c0f978cf75d86addb075ea1bb6409055ea0ab359bf057d7898a'
    }
    @{
        Name = 'AWS CLI'
        File = "AWSCLIV2-$awsVersion.msi"
        Url  = "https://awscli.amazonaws.com/AWSCLIV2-$awsVersion.msi"
        Hash = 'a896971ab9909f53f6bced3e0c3767038c1e7948a9bb11d0d49476a416111e9c'
    }
    @{
        Name = 'GitHub CLI'
        File = "gh_${ghVersion}_windows_amd64.msi"
        Url  = "https://github.com/cli/cli/releases/download/v$ghVersion/gh_${ghVersion}_windows_amd64.msi"
        Hash = '5073112b7abb5ffbba24b76aee7e89269af531218c0a42751f5f0bfb6440c2cc'
    }
    @{
        Name = 'Git'
        File = "Git-$gitVersion-64-bit.exe"
        Url  = "https://github.com/git-for-windows/git/releases/download/$gitTag/Git-$gitVersion-64-bit.exe"
        Hash = '4961a4a8cc778d8b6e00a5819e5fe4d078b754555aff7aedc2d77a5d74c2de80'
    }
)

$workDir = Join-Path $env:TEMP 'v1be-setup'
$toolsDir = 'C:\tools'
New-Item -ItemType Directory -Force -Path $workDir, $toolsDir | Out-Null

function Get-VerifiedDownload($item) {
    $path = Join-Path $workDir $item.File
    Write-Host "Downloading $($item.Name)..."
    & curl.exe -fsSL --retry 3 -o $path $item.Url
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $($item.Url)" }

    $actual = (Get-FileHash -Algorithm SHA256 -Path $path).Hash.ToLower()
    if ($actual -ne $item.Hash) {
        Remove-Item -Force $path
        throw "Hash mismatch on $($item.File): expected $($item.Hash), got $actual"
    }
    return $path
}

function Invoke-Installer($filePath, $arguments) {
    $process = Start-Process -FilePath $filePath -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "$filePath exited with $($process.ExitCode)" }
}

$paths = @{}
foreach ($item in $downloads) { $paths[$item.Name] = Get-VerifiedDownload $item }

Write-Host 'Installing Terraform...'
Expand-Archive -Force -Path $paths['Terraform'] -DestinationPath $toolsDir

Write-Host 'Installing AWS CLI...'
Invoke-Installer 'msiexec.exe' @('/i', "`"$($paths['AWS CLI'])`"", '/qn', '/norestart')

Write-Host 'Installing GitHub CLI...'
Invoke-Installer 'msiexec.exe' @('/i', "`"$($paths['GitHub CLI'])`"", '/qn', '/norestart')

Write-Host 'Installing Git...'
Invoke-Installer $paths['Git'] @('/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-', '/SUPPRESSMSGBOXES')

$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
[Environment]::SetEnvironmentVariable('Path', "$machinePath;$toolsDir", 'Machine')
$env:Path = "$machinePath;$toolsDir;" + [Environment]::GetEnvironmentVariable('Path', 'User')

Remove-Item -Recurse -Force $workDir

function Show-Check($name, $passed, $detail) {
    $label = if ($passed) { 'PASS' } else { 'FAIL' }
    $color = if ($passed) { 'Green' } else { 'Red' }
    Write-Host ('{0,-5} {1,-24} {2}' -f $label, $name, $detail) -ForegroundColor $color
}

Write-Host ''
$terraformLine = (& terraform version | Select-Object -First 1)
Show-Check 'Terraform' ($terraformLine -eq "Terraform v$terraformVersion") $terraformLine
$awsLine = (& aws --version)
Show-Check 'AWS CLI' ($awsLine -like "aws-cli/$awsVersion *") $awsLine
$ghLine = (& gh --version | Select-Object -First 1)
Show-Check 'GitHub CLI' ($ghLine -like "gh version $ghVersion *") $ghLine
$gitLine = (& git --version)
Show-Check 'Git' ($gitLine -like 'git version *') $gitLine
$bashPath = 'C:\Program Files\Git\bin\bash.exe'
Show-Check 'Bash for wizards' (Test-Path $bashPath) $bashPath

$probe = 'C:\code\v1be-infra\.write-test'
$writable = $false
try {
    Set-Content -Path $probe -Value 'x'
    Remove-Item -Force $probe
    $writable = $true
} catch {
    $writable = $false
}
Show-Check 'Code folder read-only' (-not $writable) 'C:\code\v1be-infra'

Write-Host ''
Write-Host 'Setup finished.'
