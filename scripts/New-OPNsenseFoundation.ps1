[CmdletBinding()]
param(
  [Parameter()]
  [string]$VmName = 'opnsense',

  [Parameter()]
  [string]$IsoPath = 'C:\HyperV\ISOs\OPNsense-26.1.2-dvd-amd64.iso',

  [Parameter()]
  [string]$VmRootPath = 'C:\HyperV\VMs',

  [Parameter()]
  [string]$VhdRootPath = 'C:\HyperV\VHDX',

  [Parameter()]
  [int]$VhdSizeGB = 20,

  [Parameter()]
  [int]$MemoryStartupGB = 4,

  [Parameter()]
  [int]$CpuCount = 2,

  [Parameter()]
  [string]$WanSwitchName = 'Default Switch',

  [Parameter()]
  [string]$LanTrunkSwitchName = 'LAB-TRUNK',

  [Parameter()]
  [string]$LanTrunkAdapterName = 'LAN-TRUNK',

  [Parameter()]
  [string]$WanAdapterName = 'WAN',

  [Parameter()]
  [string]$AllowedVlans = '10,20,30',

  [Parameter()]
  [switch]$StartVm
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Ensure-Switch {
  param(
    [string]$Name,
    [string]$Type
  )

  $existing = Get-VMSwitch -Name $Name -ErrorAction SilentlyContinue
  if ($null -eq $existing) {
    Write-Host "[INFO] Creating switch '$Name' ($Type)."
    New-VMSwitch -Name $Name -SwitchType $Type | Out-Null
  }
}

if (-not (Test-Path -LiteralPath $IsoPath)) {
  throw "OPNsense ISO not found at '$IsoPath'."
}

Ensure-Switch -Name $LanTrunkSwitchName -Type 'Internal'

$vmPath = Join-Path $VmRootPath $VmName
$vhdPath = Join-Path $VhdRootPath "$VmName.vhdx"
$memoryBytes = $MemoryStartupGB * 1GB
$vhdBytes = $VhdSizeGB * 1GB

New-Item -ItemType Directory -Path $VmRootPath -Force | Out-Null
New-Item -ItemType Directory -Path $VhdRootPath -Force | Out-Null
New-Item -ItemType Directory -Path $vmPath -Force | Out-Null

$vm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
if ($null -eq $vm) {
  if (Test-Path -LiteralPath $vhdPath) {
    throw "Disk already exists without VM: $vhdPath"
  }

  Write-Host "[INFO] Creating VHDX at $vhdPath ($VhdSizeGB GB dynamic)."
  New-VHD -Path $vhdPath -SizeBytes $vhdBytes -Dynamic | Out-Null

  Write-Host "[INFO] Creating VM '$VmName'."
  New-VM -Name $VmName -Generation 2 -MemoryStartupBytes $memoryBytes -Path $vmPath -NoVHD | Out-Null

  Add-VMHardDiskDrive -VMName $VmName -Path $vhdPath -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0 | Out-Null
}
else {
  Write-Host "[INFO] VM '$VmName' already exists. Applying non-destructive updates."
}

# Ensure WAN adapter
$wanAdapter = Get-VMNetworkAdapter -VMName $VmName -Name $WanAdapterName -ErrorAction SilentlyContinue
if ($null -eq $wanAdapter) {
  Add-VMNetworkAdapter -VMName $VmName -Name $WanAdapterName -SwitchName $WanSwitchName | Out-Null
}
else {
  Connect-VMNetworkAdapter -VMName $VmName -Name $WanAdapterName -SwitchName $WanSwitchName | Out-Null
}

# Ensure LAN trunk adapter
$lanAdapter = Get-VMNetworkAdapter -VMName $VmName -Name $LanTrunkAdapterName -ErrorAction SilentlyContinue
if ($null -eq $lanAdapter) {
  Add-VMNetworkAdapter -VMName $VmName -Name $LanTrunkAdapterName -SwitchName $LanTrunkSwitchName | Out-Null
}
else {
  Connect-VMNetworkAdapter -VMName $VmName -Name $LanTrunkAdapterName -SwitchName $LanTrunkSwitchName | Out-Null
}

Set-VMNetworkAdapterVlan -VMName $VmName -VMNetworkAdapterName $LanTrunkAdapterName -Trunk -AllowedVlanIdList $AllowedVlans -NativeVlanId 1

# Ensure DVD drive with ISO
$dvd = Get-VMDvdDrive -VMName $VmName -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $dvd) {
  Add-VMDvdDrive -VMName $VmName -ControllerNumber 0 -ControllerLocation 1 -Path $IsoPath | Out-Null
}
else {
  Set-VMDvdDrive -VMName $VmName -ControllerNumber $dvd.ControllerNumber -ControllerLocation $dvd.ControllerLocation -Path $IsoPath
}

Set-VM -Name $VmName -ProcessorCount $CpuCount -MemoryStartupBytes $memoryBytes -CheckpointType Disabled -AutomaticStopAction ShutDown | Out-Null
Set-VMFirmware -VMName $VmName -EnableSecureBoot Off

$dvdBoot = Get-VMDvdDrive -VMName $VmName | Select-Object -First 1
$diskBoot = Get-VMHardDiskDrive -VMName $VmName | Select-Object -First 1
if ($dvdBoot -and $diskBoot) {
  Set-VMFirmware -VMName $VmName -BootOrder @($dvdBoot, $diskBoot)
}

if ($StartVm.IsPresent) {
  $state = (Get-VM -Name $VmName).State
  if ($state -ne 'Running') {
    Start-VM -Name $VmName | Out-Null
  }
}

Write-Host "[INFO] OPNsense foundation ready for VM '$VmName'."
Write-Host "[INFO] WAN switch: $WanSwitchName | LAN trunk switch: $LanTrunkSwitchName | VLANs: $AllowedVlans"
