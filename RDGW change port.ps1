# Константы
$IPAddress = "0.0.0.0"
$HTTPPort = 4433
$UDPPort = 3391
$hklm = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\TerminalServerGateway\Config\Core"

# Создаем правила
Remove-NetFirewallRule TSG-HTTPS-Transport-In-TCP,TSG-UDP-Transport-In-UDP
New-NetFirewallRule -Name "TSG-HTTPS-Transport-In-TCP" -DisplayName "Remote Desktop Gateway HTTP Listener" -Direction Inbound -LocalPort $HTTPPort -Protocol TCP -Action Allow -Profile Any
New-NetFirewallRule -Name "TSG-UDP-Transport-In-UDP" -DisplayName "Remote Desktop Gateway UDP Listener" -Direction Inbound -LocalPort $UDPPort -Protocol UDP -Action Allow -Profile Any

# Останавливаем службу
Stop-Service TSGateway

# Изменяем IP и порт для UDP
Set-ItemProperty -Path $hklm -Name HttpIPAddress -Value $IPAddress
Set-ItemProperty -Path $hklm -Name UdpIPAddress -Value $IPAddress
Set-ItemProperty -Path $hklm -Name UdpPort -Value $UDPPort

# Изменяем IP и порт для UDP 
Get-CimInstance -Namespace root/CIMV2/TerminalServices -ClassName Win32_TSGatewayServerSettings | 
    Invoke-CimMethod -MethodName SetIPAndPort -Arguments @{TransportType = 2;IPAddress = $IPAddress; Port = $UDPPort}

Get-CimInstance -Namespace root/CIMV2/TerminalServices -ClassName Win32_TSGatewayServerSettings | 
    Invoke-CimMethod -MethodName Configure	
	
# Запуск службы
Start-Service TSGateway

# Изменяем IP и порт для TCP
Get-CimInstance -Namespace root/CIMV2/TerminalServices -ClassName Win32_TSGatewayServerSettings | 
    Invoke-CimMethod -MethodName SetIPAndPort -Arguments @{TransportType = 1;IPAddress = $IPAddress; Port = $HTTPPort; OverrideExisting = 1}
	
Get-CimInstance -Namespace root/CIMV2/TerminalServices -ClassName Win32_TSGatewayServerSettings | 
    Invoke-CimMethod -MethodName Configure
	

# Перезапуск службы
Restart-Service TSGateway

# Изменяем IP и порт для TCP 
Set-ItemProperty -Path $hklm -Name HttpsPort -Value $HTTPPort

Get-CimInstance -Namespace root/CIMV2/TerminalServices -ClassName Win32_TSGatewayServerSettings | 
    Invoke-CimMethod -MethodName SetIPAndPort -Arguments @{TransportType = 1;IPAddress = $IPAddress; Port = $HTTPPort; OverrideExisting = 1}
	
Get-CimInstance -Namespace root/CIMV2/TerminalServices -ClassName Win32_TSGatewayServerSettings | 
    Invoke-CimMethod -MethodName Configure	

Restart-Service TSGateway

# Создаем self-certificate и привязываем его
#$cert = Invoke-CimMethod -Namespace root/CIMV2/TerminalServices -ClassName Win32_TSGatewayServer -MethodName CreateSelfSignedCertificate -Arguments @{SubjectName = "SRV-RDGW.contoso.com"}
#$CertHash = $cert.CertHash
#Get-CimInstance -Namespace root/CIMV2/TerminalServices -ClassName Win32_TSGatewayServerSettings | 
#    Invoke-CimMethod -MethodName SetCertificate -Arguments @{CertHash = $CertHash}

#Get-CimInstance -Namespace root/CIMV2/TerminalServices -ClassName Win32_TSGatewayServerSettings | 
#    Invoke-CimMethod -MethodName Configure
	
#Get-CimInstance -Namespace root/CIMV2/TerminalServices -ClassName Win32_TSGatewayServerSettings | 
#    Invoke-CimMethod -MethodName SetCertificateACL -Arguments @{CertHash = $CertHash}

#Get-CimInstance -Namespace root/CIMV2/TerminalServices -ClassName Win32_TSGatewayServerSettings | 
#    Invoke-CimMethod -MethodName RefreshCertContext -Arguments @{CertHash = $CertHash}

			
#Get-CimInstance -Namespace root/CIMV2/TerminalServices -ClassName Win32_TSGatewayServerSettings | 
#  Invoke-CimMethod -MethodName Configure

#Restart-Service TSGateway