<powershell>
# First-boot setup for a Crafting sandbox Windows VM.
#
# Rendered by Terraform's templatefile(). Dollar-brace sequences are template
# placeholders, so any literal PowerShell brace expression must be doubled.
# Prefer $(...) or plain concatenation here to avoid the ambiguity entirely.
#
# Runs on every fresh instance, which includes every resume, because suspend
# destroys the instance and resume creates a new one. The data volume, however,
# persists across that cycle, so anything touching it must be idempotent and
# must never reformat an already-initialized disk.

$ErrorActionPreference = "Stop"
Start-Transcript -Path "C:\Windows\Temp\user-data.log" -Append

function Write-Step($msg) { Write-Output "=== $msg ===" }

# ---------------------------------------------------------------- OpenSSH ---
Write-Step "Installing OpenSSH server"

Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service -Name sshd -StartupType Automatic

# Default to PowerShell so `ssh host <cmd>` runs PowerShell rather than cmd.
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell `
  -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
  -PropertyType String -Force | Out-Null

if (-not (Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" `
    -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}

Start-Service sshd

# ---------------------------------------------------------- Authorized key ---
Write-Step "Installing workspace SSH public key"

# Administrators authenticate against this shared file, not the per-user
# .ssh/authorized_keys. Set-Content (not Add-Content) keeps this idempotent.
$authKeys = "C:\ProgramData\ssh\administrators_authorized_keys"
Set-Content -Path $authKeys -Value "${ssh_public_key}" -Encoding ascii

# sshd ignores the file unless it is owned tightly by SYSTEM and Administrators.
icacls.exe $authKeys /inheritance:r | Out-Null
icacls.exe $authKeys /grant "SYSTEM:F" | Out-Null
icacls.exe $authKeys /grant "BUILTIN\Administrators:F" | Out-Null

Restart-Service sshd

# ------------------------------------------------------------- Data volume ---
Write-Step "Preparing data volume"

# Three cases must all work:
#   1. First boot: the volume is RAW and needs partitioning and formatting.
#   2. After resume: the volume already holds data and must only be brought
#      online, never reformatted.
#   3. The attachment lost its drive letter and needs one reassigned.

# The attachment can lag slightly behind user-data starting.
$dataDisk = $null
foreach ($attempt in 1..30) {
  $dataDisk = Get-Disk | Where-Object { $_.Number -ne 0 } | Select-Object -First 1
  if ($dataDisk) { break }
  Write-Output "Waiting for the data volume to attach... ($attempt)"
  Start-Sleep -Seconds 10
}

if (-not $dataDisk) {
  Write-Output "WARNING: no data volume attached; skipping data volume setup"
} else {
  if ($dataDisk.IsOffline) {
    Set-Disk -Number $dataDisk.Number -IsOffline $false
  }
  if ($dataDisk.IsReadOnly) {
    Set-Disk -Number $dataDisk.Number -IsReadOnly $false
  }

  if ($dataDisk.PartitionStyle -eq "RAW") {
    Write-Output "Data volume is new; initializing and formatting"
    Initialize-Disk -Number $dataDisk.Number -PartitionStyle GPT
    New-Partition -DiskNumber $dataDisk.Number -AssignDriveLetter -UseMaximumSize |
      Format-Volume -FileSystem NTFS -NewFileSystemLabel "${data_volume_label}" -Confirm:$false
  } else {
    Write-Output "Data volume already initialized; preserving existing data"
    # Re-attached volumes sometimes come back without a drive letter.
    Get-Partition -DiskNumber $dataDisk.Number |
      Where-Object { $_.Type -ne "Reserved" -and -not $_.DriveLetter } |
      ForEach-Object { Add-PartitionAccessPath -InputObject $_ -AssignDriveLetter }
  }

  $dataVolume = Get-Partition -DiskNumber $dataDisk.Number |
    Where-Object DriveLetter | Select-Object -First 1
  if ($dataVolume) {
    Write-Output ("Data volume available at " + $dataVolume.DriveLetter + ":")
  }
}

# --------------------------------------------------------------------- RDP ---
Write-Step "Enabling Remote Desktop"

Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
  -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

# Guacamole's RDP client authenticates with a password, which requires NLA to
# accept credentials supplied up front. This is the default, but a hardened
# custom AMI may have changed it.
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" `
  -Name "UserAuthentication" -Value 1

# ------------------------------------------------------------ Customization ---
# Anything supplied through the `extra_setup` Terraform variable runs here, on
# first boot, after the platform is up. See the guide's customization section.
Write-Step "Running extra setup"

${extra_setup}

Write-Step "User-data complete"
Stop-Transcript
</powershell>
<persist>true</persist>
