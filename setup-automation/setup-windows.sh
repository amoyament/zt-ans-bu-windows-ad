#!/bin/bash

# Windows AD setup script
# This script configures the Windows AD domain controller

echo "Starting Windows AD setup..."

# Configure network settings
echo "192.168.1.10 control.lab control" >> /etc/hosts
echo "192.168.1.11 vscode.lab vscode" >> /etc/hosts
echo "192.168.1.100 windows.lab windows" >> /etc/hosts

# Install required Windows features for AD
echo "Installing Active Directory Domain Services..."
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# Configure the domain controller
echo "Configuring domain controller..."
$SecurePassword = ConvertTo-SecureString "ansible123!" -AsPlainText -Force
Install-ADDSForest -DomainName "lab.local" -DomainNetbiosName "LAB" -SafeModeAdministratorPassword $SecurePassword -Force

# Configure WinRM for Ansible
echo "Configuring WinRM for Ansible..."
winrm quickconfig -q
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="512"}'
winrm set winrm/config '@{MaxTimeoutms="1800000"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'

# Create firewall rules for WinRM
New-NetFirewallRule -DisplayName "WinRM-HTTP" -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow
New-NetFirewallRule -DisplayName "WinRM-HTTPS" -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow

# Configure IIS for web services
echo "Configuring IIS..."
Install-WindowsFeature -Name Web-Server -IncludeManagementTools
Install-WindowsFeature -Name Web-Mgmt-Console

# Create a simple test page
$html = @"
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
"@

$html | Out-File -FilePath "C:\inetpub\wwwroot\index.html" -Encoding UTF8

echo "Windows AD setup completed successfully!"
