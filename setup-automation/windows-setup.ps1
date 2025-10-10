$ErrorActionPreference = 'Stop'

Write-Host 'Starting Windows AD setup (PowerShell)...'

# Hosts entries
# Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "192.168.1.10 control.lab control"
# Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "192.168.1.11 vscode.lab vscode"
# Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "192.168.1.100 windows.lab windows"

# AD DS
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# Promote DC (skip if already promoted)
try {
  $null = (Get-Service NTDS -ErrorAction Stop)
  Write-Host 'NTDS service found; skipping forest creation'
}
catch {
  $SecurePassword = ConvertTo-SecureString 'Ansible123!' -AsPlainText -Force
  Install-ADDSForest -DomainName 'lab.local' -DomainNetbiosName 'LAB' -SafeModeAdministratorPassword $SecurePassword -Force
}

# WinRM
winrm quickconfig -q
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="512"}'
winrm set winrm/config '@{MaxTimeoutms="1800000"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'

# Firewall
New-NetFirewallRule -DisplayName 'WinRM-HTTP' -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName 'WinRM-HTTPS' -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow -ErrorAction SilentlyContinue

# IIS
Install-WindowsFeature -Name Web-Server -IncludeManagementTools
Install-WindowsFeature -Name Web-Mgmt-Console

$html = @'
<!DOCTYPE html>
<html>
<head>
    <title>Windows AD Lab</title>
</head>
<body>
    <h1>Windows AD Domain Controller</h1>
    <p>This is the Windows AD domain controller for the lab.</p>
</body>
</html>
'@
$html | Out-File -FilePath 'C:\inetpub\wwwroot\index.html' -Encoding UTF8

# Marker file on desktop to verify execution
New-Item -Path "$HOME\Desktop\MyFile.txt" -ItemType File -Force | Out-Null

Write-Host 'Windows AD setup (PowerShell) completed.'


