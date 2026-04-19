# ad-pki-lab
Home lab for Active Directory, PKI, and infrastructure automation using Hyper-V, Terraform, and PowerShell.

## Overview
Automated Active Directory / PKI lab built with:
- GitHub Actions (self-hosted runner)
- Hyper-V automation (PowerShell)
- Image-based Windows Server deployment

## Current state
- Fully automated VM provisioning (~40 seconds)
- No manual interaction (zero-click deployment)

## Hyper-V deployment workflow
`03 - Deploy Hyper-V VM` is parameterized and supports hostname automation in one run.

### Workflow inputs
- `vmName` (required): VM name in Hyper-V
- `cpu` (default `2`): vCPU count
- `ramGb` (default `4`): startup RAM in GB
- `hostname` (optional): guest hostname override (defaults to `vmName`)

### Runtime behavior
- Idempotent: if VM exists, it is reused (no delete/recreate)
- Non-destructive updates: applies CPU/RAM updates and starts VM if needed
- Hostname automation: uses PowerShell Direct after boot and renames guest if needed

### Secret required
- `LAB_LOCAL_ADMIN_PASSWORD`: local Administrator password inside the guest image


## OPNsense network foundation
Use workflow `00 - Hyper-V Network Foundation (OPNsense)` to bootstrap the Hyper-V networking base:
- creates/ensures internal trunk switch (`LAB-TRUNK` by default)
- creates/updates OPNsense VM with WAN on `Default Switch` and LAN trunk adapter
- enables trunk VLANs (default `10,20,30`) on the OPNsense LAN adapter
- attaches OPNsense ISO during VM creation and sets DVD first in boot order

This is designed to be idempotent and safe to re-run.

## Next steps
- AD DS
- Domain join automation
- PKI deployment
- Baseline hardening
- Terraform integration
