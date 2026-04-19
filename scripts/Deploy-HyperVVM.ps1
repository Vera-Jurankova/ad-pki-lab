[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$VmName,

  [Parameter()]
  [ValidateRange(1, 64)]
  [int]$CpuCount = 2,

  [Parameter()]
  [ValidateRange(1, 512)]
  [int]$MemoryStartupGB = 4,

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [string]$Hostname = $VmName,

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [string]$VhdxTemplatePath = 'C:\HyperV\images\win2022-base-silver.vhdx',

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [string]$VmRootPath = 'C:\HyperV\VMs',

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [string]$SwitchName = 'Default Switch',

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [string]$AdminUser = 'Administrator',

  [Parameter()]
  [string]$AdminPassword,

  [Parameter()]
  [ValidateRange(60, 3600)]
  [int]$GuestReadyTimeoutSec = 900
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info {
  param([string]$Message)
  Write-Host "[INFO] $Message"
}

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
    }
    catch {
      Start-Sleep -Seconds 10
    }
  }

  return $false
}

if ($Hostname.Length -gt 15) {
  throw "Hostname '$Hostname' exceeds 15 characters (NetBIOS limit)."
}

if (-not (Test-Path -LiteralPath $VhdxTemplatePath)) {
  throw "Template VHDX not found at '$VhdxTemplatePath'."
}

$vmPath = Join-Path -Path $VmRootPath -ChildPath $VmName
$vmDiskPath = Join-Path -Path $vmPath -ChildPath "$VmName.vhdx"
$memoryBytes = $MemoryStartupGB * 1GB

$existingVm = Get-VM -Name $VmName -ErrorAction SilentlyContinue

if ($null -eq $existingVm) {
  Write-Info "VM '$VmName' does not exist. Creating new VM."

  New-Item -Path $vmPath -ItemType Directory -Force | Out-Null

  if (-not (Test-Path -LiteralPath $vmDiskPath)) {
    Write-Info "Copying template disk to '$vmDiskPath'."
    Copy-Item -Path $VhdxTemplatePath -Destination $vmDiskPath -Force
  }

  New-VM -Name $VmName -Generation 2 -MemoryStartupBytes $memoryBytes -VHDPath $vmDiskPath -Path $vmPath -SwitchName $SwitchName | Out-Null

  Set-VMProcessor -VMName $VmName -Count $CpuCount
  Set-VM -Name $VmName -AutomaticCheckpointsEnabled $false | Out-Null
  Set-VMFirmware -VMName $VmName -FirstBootDevice (Get-VMHardDiskDrive -VMName $VmName)
}
else {
  Write-Info "VM '$VmName' already exists. Keeping it and applying non-destructive config updates."
  Set-VMProcessor -VMName $VmName -Count $CpuCount
  Set-VM -Name $VmName -MemoryStartupBytes $memoryBytes | Out-Null
}

$vm = Get-VM -Name $VmName
if ($vm.State -ne 'Running') {
  Write-Info "Starting VM '$VmName'."
  Start-VM -Name $VmName | Out-Null
}

if ([string]::IsNullOrWhiteSpace($AdminPassword)) {
  Write-Warning 'AdminPassword was not provided. Skipping hostname automation.'
  exit 0
}

Write-Info "Waiting for PowerShell Direct in guest '$VmName'."
$securePassword = ConvertTo-SecureString -String $AdminPassword -AsPlainText -Force
$credential = [pscredential]::new($AdminUser, $securePassword)

if (-not (Wait-GuestPowerShell -TargetVmName $VmName -Credential $credential -TimeoutSec $GuestReadyTimeoutSec)) {
  throw "Timed out waiting for PowerShell Direct on VM '$VmName'."
}

$renameResult = Invoke-Command -VMName $VmName -Credential $credential -ScriptBlock {
  param([string]$DesiredHostname)

  if ($env:COMPUTERNAME -ieq $DesiredHostname) {
    return 'already-correct'
  }

  Rename-Computer -NewName $DesiredHostname -Force
  return 'renamed'
} -ArgumentList $Hostname

if ($renameResult -eq 'renamed') {
  Write-Info "Hostname changed to '$Hostname'. Restarting guest to apply change."
  Restart-VM -Name $VmName -Force | Out-Null
}
else {
  Write-Info "Hostname already set to '$Hostname'."
}

Write-Info 'Deploy workflow completed successfully.'
