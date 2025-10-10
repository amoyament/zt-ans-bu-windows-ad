# #!/bin/bash

# # Windows AD setup script
# # This script configures the Windows AD domain controller

# echo "Starting Windows AD setup..."

# # Configure network settings
# echo "192.168.1.10 control.lab control" >> /etc/hosts
# echo "192.168.1.11 vscode.lab vscode" >> /etc/hosts
# echo "192.168.1.100 windows.lab windows" >> /etc/hosts

# # Install required Windows features for AD
# echo "Installing Active Directory Domain Services..."
# powershell -Command "Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools"

# # Configure the domain controller
# echo "Configuring domain controller..."
# powershell -Command "\$SecurePassword = ConvertTo-SecureString 'ansible123!' -AsPlainText -Force; Install-ADDSForest -DomainName 'lab.local' -DomainNetbiosName 'LAB' -SafeModeAdministratorPassword \$SecurePassword -Force"

# # Configure WinRM for Ansible
# echo "Configuring WinRM for Ansible..."
# powershell -Command "winrm quickconfig -q"
# powershell -Command "winrm set winrm/config/winrs '@{MaxMemoryPerShellMB=\"512\"}'"
# powershell -Command "winrm set winrm/config '@{MaxTimeoutms=\"1800000\"}'"
# powershell -Command "winrm set winrm/config/service '@{AllowUnencrypted=\"true\"}'"
# powershell -Command "winrm set winrm/config/service/auth '@{Basic=\"true\"}'"

# # Create firewall rules for WinRM
# powershell -Command "New-NetFirewallRule -DisplayName 'WinRM-HTTP' -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow"
# powershell -Command "New-NetFirewallRule -DisplayName 'WinRM-HTTPS' -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow"

# # Configure IIS for web services
# echo "Configuring IIS..."
# powershell -Command "Install-WindowsFeature -Name Web-Server -IncludeManagementTools"
# powershell -Command "Install-WindowsFeature -Name Web-Mgmt-Console"

# # Create a simple test page
# powershell -Command "\$html = @'
# <!DOCTYPE html>
# <html>
# <head>
#     <title>Windows AD Lab</title>
# </head>
# <body>
#     <h1>Windows AD Domain Controller</h1>
#     <p>This is the Windows AD domain controller for the lab.</p>
# </body>
# </html>
# '@; \$html | Out-File -FilePath 'C:\inetpub\wwwroot\index.html' -Encoding UTF8"

# # # Install Microsoft Edge (always install)
# # echo "Installing Microsoft Edge..."
# # powershell -Command "\
# # $ErrorActionPreference='Stop'; \
# # $winget = Get-Command winget -ErrorAction SilentlyContinue; \
# # if ($winget) { \
# #   winget install --id Microsoft.Edge -e --accept-source-agreements --accept-package-agreements --silent --source winget; \
# # } else { \
# #   [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; \
# #   $api='https://edgeupdates.microsoft.com/api/products?platform=win64'; \
# #   $data = Invoke-RestMethod -Uri $api -UseBasicParsing; \
# #   $stable = $data | Where-Object { $_.Product -eq 'Stable' } | Select-Object -First 1; \
# #   $release = $stable.Releases | Sort-Object -Property PublishedDate -Descending | Select-Object -First 1; \
# #   $artifact = $release.Artifacts | Where-Object { ($_.Type -and ($_.Type -match 'msi')) -or ($_.InstallerType -and ($_.InstallerType -match 'msi')) } | Select-Object -First 1; \
# #   if (-not $artifact) { throw 'Unable to locate MSI artifact for Microsoft Edge.' }; \
# #   $url = $artifact.Location; \
# #   $tmp = Join-Path $env:TEMP 'MicrosoftEdgeEnterpriseX64.msi'; \
# #   Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing; \
# #   Start-Process msiexec.exe -ArgumentList "/i `"$tmp`" /qn /norestart" -Wait; \
# #   Remove-Item $tmp -ErrorAction SilentlyContinue; \
# # }"

# powershell -Command 'New-Item -Path "$HOME\Desktop\MyFile.txt"'

# echo "Windows AD setup completed successfully!"
