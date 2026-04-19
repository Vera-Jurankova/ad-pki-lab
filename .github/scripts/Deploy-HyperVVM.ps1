[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$VmName,

  [Parameter()]
  [ValidateRange(1, 64)]
  [int]$CpuCount = 2,

  [Parameter()]
  [ValidateRange(1, 512)]
  [int]$MemoryStartupGB = 4,

  [Parameter()]
  [string]$Hostname = $VmName,

  [Parameter()]
  [string]$VhdxTemplatePath = 'C:\HyperV\images\win2022-base-silver.vhdx',

  [Parameter()]
  [string]$VmRootPath = 'C:\HyperV\VMs',

  [Parameter()]
  [string]$SwitchName = 'Default Switch',

  [Parameter()]
  [string]$AdminUser = 'Administrator',

  [Parameter()]
  [string]$AdminPassword,

  [Parameter()]
  [ValidateRange(60, 3600)]
  [int]$GuestReadyTimeoutSec = 900
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Wait-GuestPowerShell {
  param(
    [string]$TargetVmName,
    [pscredential]$Credential,
    [int]$TimeoutSec
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    try {
      Invoke-Command -VMName $TargetVmName -Credential $Credential -ScriptBlock { 'ready' } | Out-Null
      return $true
    } catch {
      Start-Sleep -Seconds 10
    }
  }
  return $false
}

if ($Hostname.Length -gt 15) {
  throw "Hostname '$Hostname' exceeds 15 characters."
}

if (-not (Test-Path -LiteralPath $VhdxTemplatePath)) {
  throw "Template VHDX not found at '$VhdxTemplatePath'."
}

$vmPath = Join-Path $VmRootPath $VmName
$vmDiskPath = Join-Path $vmPath "$VmName.vhdx"
$memoryBytes = $MemoryStartupGB * 1GB

$existingVm = Get-VM -Name $VmName -ErrorAction SilentlyContinue

if ($null -eq $existingVm) {
  New-Item -Path $vmPath -ItemType Directory -Force | Out-Null

  if (-not (Test-Path -LiteralPath $vmDiskPath)) {
    Copy-Item -Path $VhdxTemplatePath -Destination $vmDiskPath -Force
  }

  New-VM -Name $VmName -Generation 2 -MemoryStartupBytes $memoryBytes -VHDPath $vmDiskPath -Path $vmPath -SwitchName $SwitchName | Out-Null
  Set-VMProcessor -VMName $VmName -Count $CpuCount
  Set-VM -Name $VmName -AutomaticCheckpointsEnabled $false | Out-Null
  Set-VMFirmware -VMName $VmName -FirstBootDevice (Get-VMHardDiskDrive -VMName $VmName)
}
else {
  Set-VMProcessor -VMName $VmName -Count $CpuCount
  Set-VM -Name $VmName -MemoryStartupBytes $memoryBytes | Out-Null
}

$vm = Get-VM -Name $VmName
if ($vm.State -ne 'Running') {
  Start-VM -Name $VmName | Out-Null
}

if ([string]::IsNullOrWhiteSpace($AdminPassword)) {
  Write-Warning 'AdminPassword missing, skipping hostname automation.'
  exit 0
}

$securePassword = ConvertTo-SecureString -String $AdminPassword -AsPlainText -Force
$credential = [pscredential]::new($AdminUser, $securePassword)

if (-not (Wait-GuestPowerShell -TargetVmName $VmName -Credential $credential -TimeoutSec $GuestReadyTimeoutSec)) {
  throw "Timed out waiting for PowerShell Direct on '$VmName'."
}

$renameResult = Invoke-Command -VMName $VmName -Credential $credential -ScriptBlock {
  param([string]$DesiredHostname)

  if ($env:COMPUTERNAME -ieq $DesiredHostname) { return 'already-correct' }
  Rename-Computer -NewName $DesiredHostname -Force
  return 'renamed'
} -ArgumentList $Hostname

if ($renameResult -eq 'renamed') {
  Restart-VM -Name $VmName -Force | Out-Null
}