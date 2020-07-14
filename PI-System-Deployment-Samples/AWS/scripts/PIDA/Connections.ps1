# ***********************************************************************
# * DISCLAIMER:
# * All sample code is provided by OSIsoft for illustrative purposes only.
# * These examples have not been thoroughly tested under all conditions.
# * OSIsoft provides no guarantee nor implies any reliability, 
# * serviceability, or function of these programs.
# * ALL PROGRAMS CONTAINED HEREIN ARE PROVIDED TO YOU "AS IS" 
# * WITHOUT ANY WARRANTIES OF ANY KIND. ALL WARRANTIES INCLUDING 
# * THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY
# * AND FITNESS FOR A PARTICULAR PURPOSE ARE EXPRESSLY DISCLAIMED.
# ************************************************************************

param(
	[Parameter(Position=0, Mandatory=$true)]
	[string] $PIServerName,
	
	[Parameter(Position=1, Mandatory=$false)]
	[DateTime] $StartTime,
	
	[Parameter(Position=2, Mandatory=$false)]
	[DateTime] $EndTime)

Start-Transcript -Path C:\cfn\log\$($MyInvocation.MyCommand.Name).log -Append

$srv = Get-PIDataArchiveConnectionConfiguration -Name $PIServerName -ErrorAction Stop
$connection = Connect-PIDataArchive -PIDataArchiveConnectionConfiguration $srv -ErrorAction Stop

[Version] $v390 = "3.4.390"
[Version] $v385 = "3.4.385"

[bool] $is390 = $false
[bool] $is385 = $false

if ($connection.ServerVersion -gt $v390)
{
	$is390 = $true
}
elseif ($connection.ServerVersion -gt $v385)
{
	$is385 = $true
}
else
{
	"Unsupported PI server version found."
	exit
}

# If StartTime is not passed in, get the startup time of pinetmgr and use that as the StartTime
if ($StartTime -eq $null)
{
	$service = Get-WmiObject win32_service -filter "name = 'pinetmgr'" -ComputerName $connection.Address.Host
	$serverStartup = ((Get-Date) - ([wmi]'').ConvertToDateTime((Get-WmiObject Win32_Process -ComputerName $connection.Address.Host -filter "ProcessID = '$($service.ProcessId)'").CreationDate))
	
	$StartTime = (Get-Date) - $serverStartup
}

# If EndTime is not passed in, use current time as end time
if ($EndTime -eq $null)
{
	$EndTime = Get-Date
}

# Get all the connections since StartTime
# Message ID's are the following:
# 7039 - Begin connection
# 7080 - Connection information
# 7096 - End connection
# 7121 - End connection
# 7133 - Connection Statistics
$messages = Get-PIMessage -Connection $connection -StartTime $StartTime -EndTime $EndTime -ID 7039,7080,7096,7121,7133

# Store all the active connection information in a hashtable of obects.
# The hashtable is indexed by Connection ID
# When a connection is completed, move the entry from the Hashtable into an array
# This is to handle reused Connection IDs
[Hashtable] $activeConnections = @{}
[Array] $closedConnections = @()

foreach($item in $messages)
{
	if ($item.ID -eq 7039)
	{
		# begin connection message
		if ($item.Message -match "Process name:\s*(.*) ID: (.*)" -eq $true)
		{
			# $Matches[1] Process Name
			# $Matches[2] Connection ID
			
			$id = $Matches[2].Trim() -as [Int32]
			if ($id -ne $null -and $activeConnections.ContainsKey($id) -eq $false)
			{
				#Parse out connection information
				$appInfo = $Matches[1]
				if ($appInfo -match "(.*)\((.*)\):(.*)\((.*)\)" -eq $true)
				{
					$isRemote = $true
					$appName = $Matches[1]
					$appPID = $Matches[2]
				}
				elseif ($appInfo -match "(.*)\((.*)\)" -eq $true)
				{
					$isRemote = $false
					$appName = $Matches[1]
					$appPID = $Matches[2]
				}
				else
				{
					$isRemote = $null
					$appName = $appInfo
					$appPID = $null
				}
				
				$temp = New-Object PSCustomObject
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "ID" -Value $id
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "ApplicationName" -Value $appName
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "ApplicationPID" -Value $appPID
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "IsRemote" -Value $isRemote
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "PIUser" -Value $null
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "OSUser" -Value $null
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "IPAddress" -Value $null
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "Duration" -Value $null
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "StartTime" -Value $item.LogTime
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "EndTime" -Value $null
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "KBSent" -Value $null
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "KBReceived" -Value $null
				Add-Member -InputObject $temp -MemberType NoteProperty -Name "DisconnectReason" -Value $null
				$activeConnections.Add($id, $temp)
			}
		}
	}
	elseif ($item.ID -eq 7080)
	{
		# connection information message 3.4.390
		if ($is390 -eq $true)
		{
			if ($item.Message -match "Connection ID: (.*) ; Process name: (.*) ; User: (.*) ; OS User: (.*) ; Hostname: (.*) IP: (.*) ; AppID: (.*) ; AppName: (.*)" -eq $true)
			{
				# $Matches[1] Connection ID
				# $Matches[3] PIUser
				# $Matches[4] OSUser
				# $Matches[6] IP address
				
				$id = $Matches[1].Trim() -as [Int32]
				if ($id -ne $null -and $activeConnections.ContainsKey($id) -eq $true)
				{
					$activeConnections[$id].PIUser = $Matches[3].Trim()
					$activeConnections[$id].OSUser = $Matches[4].Trim()
					$activeConnections[$id].IPAddress = $Matches[6].Trim()
				}
			}
		}
		# connection information message 3.4.385
		elseif ($is385 -eq $true)
		{
			if ($item.Message -match "Connection ID: (.*) ; Process name: (.*) ; User: (.*) ; OS User: (.*) ; IP: (.*) ; AppID: (.*) ; AppName: (.*)" -eq $true)
			{
				# $Matches[1] Connection ID
				# $Matches[3] PIUser
				# $Matches[4] OSUser
				# $Matches[5] IP address
				
				$id = $Matches[1].Trim() -as [Int32]
				if ($id -ne $null -and $activeConnections.ContainsKey($id) -eq $true)
				{
					$activeConnections[$id].PIUser = $Matches[3].Trim()
					$activeConnections[$id].OSUser = $Matches[4].Trim()
					$activeConnections[$id].IPAddress = $Matches[5].Trim()
				}
			}
		}
	}
	elseif ($item.ID -eq 7096 -or $item.ID -eq 7121)
	{
		#end connection message
		if ($item.Message -match "Deleting connection: (.*), (.*), ID: (.*) (.*)" -eq $true)
		{
			# $Matches[1] Application name
			# $Matches[2] Disconnect reason
			# $Matches[3] Connection ID
			# $Matches[4] Connection address
			
			$id = $Matches[3].Trim() -as [Int32]
			if ($id -ne $null -and $activeConnections.ContainsKey($id) -eq $true)
			{
				$activeConnections[$id].DisconnectReason = $Matches[2].Trim()
				$activeConnections[$id].EndTime = $item.LogTime
				if ($activeConnections[$id].StartTime -ne $null)
				{
					$activeConnections[$id].Duration = $activeConnections[$id].EndTime - $activeConnections[$id].StartTime
				}
			}
		}
	}
	elseif ($item.ID -eq 7133)
	{
		#Connection Statistics message
		if ($item.Message -match "ID: (.*); Duration: (.*); kbytes sent: (.*); kbytes recv: (.*); app: (.*); user: (.*); osuser: (.*); trust: (.*); ip address: (.*); ip host: (.*)" -eq $true)
		{
			# $Matches[1] Connection ID
			# $Matches[3] KBSent
			# $Matches[4] KBReceived
			
			$id = $Matches[1].Trim() -as [Int32]
			if ($id -ne $null -and $activeConnections.ContainsKey($id) -eq $true)
			{
				$activeConnections[$id].KBSent = $Matches[3] -as [Float]
				$activeConnections[$id].KBReceived = $Matches[4] -as [Float]
				
				# Copy connection information into closed connections array
				$closedConnections += $activeConnections[$id]
				# Remove active connection
				$activeConnections.Remove($id)
			}
		}
	}
}

# Write all connections to output pipeline
$activeConnections.Values
$closedConnections
# SIG # Begin signature block
# MIIbywYJKoZIhvcNAQcCoIIbvDCCG7gCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCs/5XvvtNqgBYt
# 2qUSmB7D1WrmVKMvH1dvjV9nTTp6tKCCCo4wggUwMIIEGKADAgECAhAECRgbX9W7
# ZnVTQ7VvlVAIMA0GCSqGSIb3DQEBCwUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNV
# BAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0xMzEwMjIxMjAwMDBa
# Fw0yODEwMjIxMjAwMDBaMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2Vy
# dCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lD
# ZXJ0IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EwggEiMA0GCSqGSIb3
# DQEBAQUAA4IBDwAwggEKAoIBAQD407Mcfw4Rr2d3B9MLMUkZz9D7RZmxOttE9X/l
# qJ3bMtdx6nadBS63j/qSQ8Cl+YnUNxnXtqrwnIal2CWsDnkoOn7p0WfTxvspJ8fT
# eyOU5JEjlpB3gvmhhCNmElQzUHSxKCa7JGnCwlLyFGeKiUXULaGj6YgsIJWuHEqH
# CN8M9eJNYBi+qsSyrnAxZjNxPqxwoqvOf+l8y5Kh5TsxHM/q8grkV7tKtel05iv+
# bMt+dDk2DZDv5LVOpKnqagqrhPOsZ061xPeM0SAlI+sIZD5SlsHyDxL0xY4PwaLo
# LFH3c7y9hbFig3NBggfkOItqcyDQD2RzPJ6fpjOp/RnfJZPRAgMBAAGjggHNMIIB
# yTASBgNVHRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAK
# BggrBgEFBQcDAzB5BggrBgEFBQcBAQRtMGswJAYIKwYBBQUHMAGGGGh0dHA6Ly9v
# Y3NwLmRpZ2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3aHR0cDovL2NhY2VydHMuZGln
# aWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNydDCBgQYDVR0fBHow
# eDA6oDigNoY0aHR0cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJl
# ZElEUm9vdENBLmNybDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0Rp
# Z2lDZXJ0QXNzdXJlZElEUm9vdENBLmNybDBPBgNVHSAESDBGMDgGCmCGSAGG/WwA
# AgQwKjAoBggrBgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAK
# BghghkgBhv1sAzAdBgNVHQ4EFgQUWsS5eyoKo6XqcQPAYPkt9mV1DlgwHwYDVR0j
# BBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wDQYJKoZIhvcNAQELBQADggEBAD7s
# DVoks/Mi0RXILHwlKXaoHV0cLToaxO8wYdd+C2D9wz0PxK+L/e8q3yBVN7Dh9tGS
# dQ9RtG6ljlriXiSBThCk7j9xjmMOE0ut119EefM2FAaK95xGTlz/kLEbBw6RFfu6
# r7VRwo0kriTGxycqoSkoGjpxKAI8LpGjwCUR4pwUR6F6aGivm6dcIFzZcbEMj7uo
# +MUSaJ/PQMtARKUT8OZkDCUIQjKyNookAv4vcn4c10lFluhZHen6dGRrsutmQ9qz
# sIzV6Q3d9gEgzpkxYz0IGhizgZtPxpMQBvwHgfqL2vmCSfdibqFT+hKUGIUukpHq
# aGxEMrJmoecYpJpkUe8wggVWMIIEPqADAgECAhAFTTVZN0yftPMcszD508Q/MA0G
# CSqGSIb3DQEBCwUAMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0
# IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EwHhcNMTkwNjE3MDAwMDAw
# WhcNMjAwNzAxMTIwMDAwWjCBkjELMAkGA1UEBhMCVVMxCzAJBgNVBAgTAkNBMRQw
# EgYDVQQHEwtTYW4gTGVhbmRybzEVMBMGA1UEChMMT1NJc29mdCwgTExDMQwwCgYD
# VQQLEwNEZXYxFTATBgNVBAMTDE9TSXNvZnQsIExMQzEkMCIGCSqGSIb3DQEJARYV
# c21hbmFnZXJzQG9zaXNvZnQuY29tMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIB
# CgKCAQEAqbP+VTz8qtsq4SWhF7LsXqeDGyUwtDpf0vlSg+aQh2fOqJhW2uiPa1GO
# M5+xbr+RhTTWzJX2vEwqSIzN43ktTdgcVT9Bf5W2md+RCYE1D17jGlj5sCFTS4eX
# Htm+lFoQF0donavbA+7+ggd577FdgOnjuYxEpZe2lbUyWcKOHrLQr6Mk/bKjcYSY
# B/ipNK4hvXKTLEsN7k5kyzRkq77PaqbVAQRgnQiv/Lav5xWXuOn7M94TNX4+1Mk8
# 74nuny62KLcMRtjPCc2aWBpHmhD3wPcUVvTW+lGwEaT0DrCwcZDuG/Igkhqj/8Rf
# HYfnZQtWMnBFAHcuA4jJgmZ7xYMPoQIDAQABo4IBxTCCAcEwHwYDVR0jBBgwFoAU
# WsS5eyoKo6XqcQPAYPkt9mV1DlgwHQYDVR0OBBYEFNcTKM3o/Fjj9J3iOakcmKx6
# CPetMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzB3BgNVHR8E
# cDBuMDWgM6Axhi9odHRwOi8vY3JsMy5kaWdpY2VydC5jb20vc2hhMi1hc3N1cmVk
# LWNzLWcxLmNybDA1oDOgMYYvaHR0cDovL2NybDQuZGlnaWNlcnQuY29tL3NoYTIt
# YXNzdXJlZC1jcy1nMS5jcmwwTAYDVR0gBEUwQzA3BglghkgBhv1sAwEwKjAoBggr
# BgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAIBgZngQwBBAEw
# gYQGCCsGAQUFBwEBBHgwdjAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNl
# cnQuY29tME4GCCsGAQUFBzAChkJodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20v
# RGlnaUNlcnRTSEEyQXNzdXJlZElEQ29kZVNpZ25pbmdDQS5jcnQwDAYDVR0TAQH/
# BAIwADANBgkqhkiG9w0BAQsFAAOCAQEAigLIcsGUWzXlZuVQY8s1UOxYgch5qO1Y
# YEDFF8abzJQ4RiB8rcdoRWjsfpWxtGOS0wkA2CfyuWhjO/XqgmYJ8AUHIKKCy6QE
# 31/I6izI6iDCg8X5lSR6nKsB2BCZCOnGJOEi3r+WDS18PMuW24kaBo1ezx6KQOx4
# N0qSrMJqJRXfPHpl3WpcLs3VA1Gew9ATOQ9IXbt8QCvyMICRJxq4heHXPLE3EpK8
# 2wlBKwX3P4phapmEUOWxB45QOcRJqgahe9qIALbLS+i5lxV+eX/87YuEiyDtGfH+
# dAbq5BqlYz1Fr8UrWeR3KIONPNtkm2IFHNMdpsgmKwC/Xh3nC3b27DGCEJMwghCP
# AgEBMIGGMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAX
# BgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIg
# QXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0ECEAVNNVk3TJ+08xyzMPnTxD8wDQYJ
# YIZIAWUDBAIBBQCggZ4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYB
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIH6eEzuuEDcR
# luFlOmh6RjAf809RhM1rgkp5obYIxCmYMDIGCisGAQQBgjcCAQwxJDAioSCAHmh0
# dHA6Ly90ZWNoc3VwcG9ydC5vc2lzb2Z0LmNvbTANBgkqhkiG9w0BAQEFAASCAQAN
# q27YG2Iod3Ic3q58RA8KVdAsuxU/WiLPja/1W5QzUjE2KldHvGSJY6LSXJZIzHNZ
# lArfEaJBQj6cA0pZWM3eOj2Fe5Ik4+wKtNXEI41r5189HH6ZQ3M6sT6rOhOjya/3
# 4GdxUWCZvuBN4pxqE8obp1dhy0JK3oaYU6pPYsg1viOENMsz1Xn0gcDNPL4WSJoR
# XHYjbut+0tcUAA/s5VbvPMsyd6mvlB8I0pNQRO1R573Jx8G+ffq9CcDHAEwq+IKa
# V2SEClvpopLuKBSACqqK/+5kpoKUGIyEgO0Un/Mw6pi/yvfrUyhqerfDF8Oza4Vs
# EWVd0djyb9zBWNe/jf5UoYIOPDCCDjgGCisGAQQBgjcDAwExgg4oMIIOJAYJKoZI
# hvcNAQcCoIIOFTCCDhECAQMxDTALBglghkgBZQMEAgEwggEOBgsqhkiG9w0BCRAB
# BKCB/gSB+zCB+AIBAQYLYIZIAYb4RQEHFwMwMTANBglghkgBZQMEAgEFAAQgqrQf
# qG6xG47d9Dgm3XNhd9i85XKAzt2NlqBIe6U/JcQCFH+Ua0iaR+zj7ZHWlD0r7NTl
# sFjkGA8yMDIwMDMzMDE1NDIwN1owAwIBHqCBhqSBgzCBgDELMAkGA1UEBhMCVVMx
# HTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9uMR8wHQYDVQQLExZTeW1hbnRl
# YyBUcnVzdCBOZXR3b3JrMTEwLwYDVQQDEyhTeW1hbnRlYyBTSEEyNTYgVGltZVN0
# YW1waW5nIFNpZ25lciAtIEczoIIKizCCBTgwggQgoAMCAQICEHsFsdRJaFFE98mJ
# 0pwZnRIwDQYJKoZIhvcNAQELBQAwgb0xCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5W
# ZXJpU2lnbiwgSW5jLjEfMB0GA1UECxMWVmVyaVNpZ24gVHJ1c3QgTmV0d29yazE6
# MDgGA1UECxMxKGMpIDIwMDggVmVyaVNpZ24sIEluYy4gLSBGb3IgYXV0aG9yaXpl
# ZCB1c2Ugb25seTE4MDYGA1UEAxMvVmVyaVNpZ24gVW5pdmVyc2FsIFJvb3QgQ2Vy
# dGlmaWNhdGlvbiBBdXRob3JpdHkwHhcNMTYwMTEyMDAwMDAwWhcNMzEwMTExMjM1
# OTU5WjB3MQswCQYDVQQGEwJVUzEdMBsGA1UEChMUU3ltYW50ZWMgQ29ycG9yYXRp
# b24xHzAdBgNVBAsTFlN5bWFudGVjIFRydXN0IE5ldHdvcmsxKDAmBgNVBAMTH1N5
# bWFudGVjIFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0EwggEiMA0GCSqGSIb3DQEBAQUA
# A4IBDwAwggEKAoIBAQC7WZ1ZVU+djHJdGoGi61XzsAGtPHGsMo8Fa4aaJwAyl2pN
# yWQUSym7wtkpuS7sY7Phzz8LVpD4Yht+66YH4t5/Xm1AONSRBudBfHkcy8utG7/Y
# lZHz8O5s+K2WOS5/wSe4eDnFhKXt7a+Hjs6Nx23q0pi1Oh8eOZ3D9Jqo9IThxNF8
# ccYGKbQ/5IMNJsN7CD5N+Qq3M0n/yjvU9bKbS+GImRr1wOkzFNbfx4Dbke7+vJJX
# cnf0zajM/gn1kze+lYhqxdz0sUvUzugJkV+1hHk1inisGTKPI8EyQRtZDqk+scz5
# 1ivvt9jk1R1tETqS9pPJnONI7rtTDtQ2l4Z4xaE3AgMBAAGjggF3MIIBczAOBgNV
# HQ8BAf8EBAMCAQYwEgYDVR0TAQH/BAgwBgEB/wIBADBmBgNVHSAEXzBdMFsGC2CG
# SAGG+EUBBxcDMEwwIwYIKwYBBQUHAgEWF2h0dHBzOi8vZC5zeW1jYi5jb20vY3Bz
# MCUGCCsGAQUFBwICMBkaF2h0dHBzOi8vZC5zeW1jYi5jb20vcnBhMC4GCCsGAQUF
# BwEBBCIwIDAeBggrBgEFBQcwAYYSaHR0cDovL3Muc3ltY2QuY29tMDYGA1UdHwQv
# MC0wK6ApoCeGJWh0dHA6Ly9zLnN5bWNiLmNvbS91bml2ZXJzYWwtcm9vdC5jcmww
# EwYDVR0lBAwwCgYIKwYBBQUHAwgwKAYDVR0RBCEwH6QdMBsxGTAXBgNVBAMTEFRp
# bWVTdGFtcC0yMDQ4LTMwHQYDVR0OBBYEFK9j1sqjToVy4Ke8QfMpojh/gHViMB8G
# A1UdIwQYMBaAFLZ3+mlIR59TEtXC6gcydgfRlwcZMA0GCSqGSIb3DQEBCwUAA4IB
# AQB16rAt1TQZXDJF/g7h1E+meMFv1+rd3E/zociBiPenjxXmQCmt5l30otlWZIRx
# MCrdHmEXZiBWBpgZjV1x8viXvAn9HJFHyeLojQP7zJAv1gpsTjPs1rSTyEyQY0g5
# QCHE3dZuiZg8tZiX6KkGtwnJj1NXQZAv4R5NTtzKEHhsQm7wtsX4YVxS9U72a433
# Snq+8839A9fZ9gOoD+NT9wp17MZ1LqpmhQSZt/gGV+HGDvbor9rsmxgfqrnjOgC/
# zoqUywHbnsc4uw9Sq9HjlANgCk2g/idtFDL8P5dA4b+ZidvkORS92uTTw+orWrOV
# WFUEfcea7CMDjYUq0v+uqWGBMIIFSzCCBDOgAwIBAgIQe9Tlr7rMBz+hASMEIkFN
# EjANBgkqhkiG9w0BAQsFADB3MQswCQYDVQQGEwJVUzEdMBsGA1UEChMUU3ltYW50
# ZWMgQ29ycG9yYXRpb24xHzAdBgNVBAsTFlN5bWFudGVjIFRydXN0IE5ldHdvcmsx
# KDAmBgNVBAMTH1N5bWFudGVjIFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0EwHhcNMTcx
# MjIzMDAwMDAwWhcNMjkwMzIyMjM1OTU5WjCBgDELMAkGA1UEBhMCVVMxHTAbBgNV
# BAoTFFN5bWFudGVjIENvcnBvcmF0aW9uMR8wHQYDVQQLExZTeW1hbnRlYyBUcnVz
# dCBOZXR3b3JrMTEwLwYDVQQDEyhTeW1hbnRlYyBTSEEyNTYgVGltZVN0YW1waW5n
# IFNpZ25lciAtIEczMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEArw6K
# qvjcv2l7VBdxRwm9jTyB+HQVd2eQnP3eTgKeS3b25TY+ZdUkIG0w+d0dg+k/J0oz
# Tm0WiuSNQI0iqr6nCxvSB7Y8tRokKPgbclE9yAmIJgg6+fpDI3VHcAyzX1uPCB1y
# SFdlTa8CPED39N0yOJM/5Sym81kjy4DeE035EMmqChhsVWFX0fECLMS1q/JsI9Kf
# DQ8ZbK2FYmn9ToXBilIxq1vYyXRS41dsIr9Vf2/KBqs/SrcidmXs7DbylpWBJiz9
# u5iqATjTryVAmwlT8ClXhVhe6oVIQSGH5d600yaye0BTWHmOUjEGTZQDRcTOPAPs
# twDyOiLFtG/l77CKmwIDAQABo4IBxzCCAcMwDAYDVR0TAQH/BAIwADBmBgNVHSAE
# XzBdMFsGC2CGSAGG+EUBBxcDMEwwIwYIKwYBBQUHAgEWF2h0dHBzOi8vZC5zeW1j
# Yi5jb20vY3BzMCUGCCsGAQUFBwICMBkaF2h0dHBzOi8vZC5zeW1jYi5jb20vcnBh
# MEAGA1UdHwQ5MDcwNaAzoDGGL2h0dHA6Ly90cy1jcmwud3Muc3ltYW50ZWMuY29t
# L3NoYTI1Ni10c3MtY2EuY3JsMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1Ud
# DwEB/wQEAwIHgDB3BggrBgEFBQcBAQRrMGkwKgYIKwYBBQUHMAGGHmh0dHA6Ly90
# cy1vY3NwLndzLnN5bWFudGVjLmNvbTA7BggrBgEFBQcwAoYvaHR0cDovL3RzLWFp
# YS53cy5zeW1hbnRlYy5jb20vc2hhMjU2LXRzcy1jYS5jZXIwKAYDVR0RBCEwH6Qd
# MBsxGTAXBgNVBAMTEFRpbWVTdGFtcC0yMDQ4LTYwHQYDVR0OBBYEFKUTAamfhcwb
# bhYeXzsxqnk2AHsdMB8GA1UdIwQYMBaAFK9j1sqjToVy4Ke8QfMpojh/gHViMA0G
# CSqGSIb3DQEBCwUAA4IBAQBGnq/wuKJfoplIz6gnSyHNsrmmcnBjL+NVKXs5Rk7n
# fmUGWIu8V4qSDQjYELo2JPoKe/s702K/SpQV5oLbilRt/yj+Z89xP+YzCdmiWRD0
# Hkr+Zcze1GvjUil1AEorpczLm+ipTfe0F1mSQcO3P4bm9sB/RDxGXBda46Q71Wkm
# 1SF94YBnfmKst04uFZrlnCOvWxHqcalB+Q15OKmhDc+0sdo+mnrHIsV0zd9HCYbE
# /JElshuW6YUI6N3qdGBuYKVWeg3IRFjc5vlIFJ7lv94AvXexmBRyFCTfxxEsHwA/
# w0sUxmcczB4Go5BfXFSLPuMzW4IPxbeGAk5xn+lmRT92MYICWjCCAlYCAQEwgYsw
# dzELMAkGA1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9uMR8w
# HQYDVQQLExZTeW1hbnRlYyBUcnVzdCBOZXR3b3JrMSgwJgYDVQQDEx9TeW1hbnRl
# YyBTSEEyNTYgVGltZVN0YW1waW5nIENBAhB71OWvuswHP6EBIwQiQU0SMAsGCWCG
# SAFlAwQCAaCBpDAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwHAYJKoZIhvcN
# AQkFMQ8XDTIwMDMzMDE1NDIwN1owLwYJKoZIhvcNAQkEMSIEIPHtO8MaY2yreimG
# ZppKB6I0qxp4TUEJpuZmOo/TSHuYMDcGCyqGSIb3DQEJEAIvMSgwJjAkMCIEIMR0
# znYAfQI5Tg2l5N58FMaA+eKCATz+9lPvXbcf32H4MAsGCSqGSIb3DQEBAQSCAQAM
# jAE1pLDA0hDMmCvWfpQzyVBQvKVqMAvgO1gOqOgX93a6RkBYm0QmQEJbOOFq/Zr2
# D1ie8h1PEFbkly4wU34PE2yWutKHplsrHUvsPTFiy1iAv8k/F5ENER4ByER12XkC
# mRwBhErWtzFKpSNywK7+n3RwaVsHJIBoSv3pVB0DjXM6AutP8POszqYPWgon39m5
# dCWW5RE2CWKFrkbMV6t4TxSuY7rxzqjOrBOeo7sHkvsDk5TjREXyoq7SmsjGxx6/
# FSKlWUCP1bUXcbm6QfLNg8HFk9/QDSzjY0t1CIoPQ1txYE29Cuu7QiyzQ5VQHJ9U
# 4XsRlBMFNHvB5LDj/45O
# SIG # End signature block
