<#======================================================================================
         File Name : SvcAcctPwdRefresh.ps1
   Original Author : Kenneth C. Mazie (kcmjr AT kcmjr.com)
                   :
       Description : Will refresh a list of service account passwords from an encrypted file.
                   : The script can create the encrypted file and also decode it.
                   :
             Notes : Command line options: (default is $false unless noted)
                   : $Debug - $true/$false. Use for debugging
                   : $Decode - $true/$false. Set to $true to reverse the encryption to the console !!! ONLY !!!
                   : $Enabled - $true/$false. Set to $true to perform the reset (defaults to $false to be safe)
                   : $Console - $true/$false. Set to $true to display output to console
                   : $Testmode - $true/$false. Enabled "what if" mode.
                   :
          Warnings : Yes Virginia, this will reset your passwords. Use it wisely.
                   :
             Legal : Public Domain. Modify and redistribute freely. No rights reserved.
                   : SCRIPT PROVIDED "AS IS" WITHOUT WARRANTIES OR GUARANTEES OF
                   : ANY KIND. USE AT YOUR OWN RISK. NO TECHNICAL SUPPORT PROVIDED.
                   :
           Credits : Code snippets and/or ideas came from many sources including but
                   : not limited to the following:
                   :
    Last Update by : Kenneth C. Mazie
   Version History : v1.00 - 04-07-15 - Original
    Change History : v1.10 - 10-05-16 - Added external config file
                   : v1.20 - 09-17-18 - Added credential to XML file. Added test options. Removed Quest requirement.
                   : Added more info to console output.
                   : v1.30 - 09-17-18 - Replaced line that adds user name to email report.
                   : v1.40 - 09-18-18 - Fixed issue with secure string input to setad-accountpassword command.
                   : v1.50 - 09-19-18 - Added color to email HTML. Switched config file name to use script name.
                   :
=======================================================================================#>

<#PSScriptInfo
.VERSION 1.50
.AUTHOR Kenneth C. Mazie (kcmjr AT kcmjr.com)
.DESCRIPTION
Creates an AES encrypted password file in the script folder. Reads and decrypts the file and will reset AD passwords
using the results. Can also read the file and display original passwords to console. Use for scheduled refresh of
service account passwords that cannot change but still need to be refreshed. Emails results.
#>
Param (
    [switch]$Debug = $False,                          #--[ Set via command line to true to disable reset action and email only to alt
    [switch]$Decode = $False,   
    [switch]$Enabled = $False,                        #--[ Blocked by default. Force to true via command line to perform update
    [switch]$Console = $False,
    [switch]$TestMode = $false                        #--[ Enables "whatif" mode if set to true from command line
 )

Clear-Host
if (!(Get-Module ActiveDirectory)){Import-Module "activedirectory" -ErrorAction SilentlyContinue}
[void][Reflection.Assembly]::LoadWithPartialName("System.Security")

$SendEmail = $true                                                              #--[ Set to true to email results
$ErrorActionPreference = "Stop" #ilentlyContinue" #--[ Error action preference.

#--[ Hard settings for Testing ]----------------------
#$Enabled = $true
#$Decode = $true
#$Console = $true
#$TestRun = $true
#$Debug = $true
#-----------------------------------------------------

If ($Debug){
    $Script:Debug = $True
    $Script:Console = $True
}
If ($Decode){
    $Script:Console = $True
}
If ($Enabled){$Script:Enabled = $True}
If ($Console){$Script:Console = $True}
If ($TestRun){$Script:TestRun = $True}
If ($Script:Decode){
    $Script:Enabled = $False
    $Script:SendEmail = $False
    $Script:Console = $True
}

#--[ Read and load configuration file ]-----------------------------------------
$Computer = $Env:ComputerName
$Script:ScriptName = ($MyInvocation.MyCommand.Name).split(".")[0] 
$Script:ConfigFile = "$PSScriptRoot\$ScriptName.xml"  
If (!(Test-Path $Script:ConfigFile)){                                          #--[ Error out if configuration file doesn't exist ]--
      Write-host "MISSING CONFIG FILE. Script aborted." -ForegroundColor red
      break
}Else{
    [xml]$Script:Configuration = Get-Content "$Script:ConfigFile"  #--[ Load configuration ]--
    $Script:ScriptName = $Script:Configuration.Settings.General.ReportTitle     
    $Script:InputFile = $Script:Configuration.Settings.General.InputFile     
    $Script:SecureFile = $Script:Configuration.Settings.General.SecureFile
    $Script:MaxDays = $Script:Configuration.Settings.General.MaxDays
    $Script:DebugUser = $Script:Configuration.Settings.Email.DebugUser
    $Script:DebugSubject = $Script:Configuration.Settings.Email.DebugSubject 
    $Script:EmailTo = $Script:Configuration.Settings.Email.To
    $Script:EmailHTML = $Script:Configuration.Settings.Email.HTML
    $Script:EmailSubject = $Script:Configuration.Settings.Email.Subject
    $Script:EmailFrom = $Script:Configuration.Settings.Email.From
    $Script:EmailDomain = $Script:Configuration.Settings.Email.Domain
    $Script:SmtpServer = $Script:Configuration.Settings.Email.SmtpServer
    $Script:UserName = $Script:Configuration.Settings.Credentials.Username    
    $Script:EncryptedPW = $Script:Configuration.Settings.Credentials.Password
    $Script:Base64String = $Script:Configuration.Settings.Credentials.Key   
    $ByteArray = [System.Convert]::FromBase64String($Base64String)
    $Script:Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $UserName, ($EncryptedPW | ConvertTo-SecureString -Key $ByteArray)
    $Script:Password = $Credential.GetNetworkCredential().Password    
    $Script:Passphrase = $Script:Configuration.Settings.Credentials.Passphrase
    $Script:Salt = $Script:Configuration.Settings.Credentials.Salt
    $Script:Init = $Script:Configuration.Settings.Credentials.Init
    $Script:EventlogName = $Script:Configuration.Settings.General.EventlogName
    $Script:EventlogID = $Script:Configuration.Settings.General.EventlogID
    $Script:EventlogType = $Script:Configuration.Settings.General.EventlogType
    $Script:EmailAttach1 = $Script:Configuration.Settings.Email.Attachments.Attach1
}

If ($Script:Debug){
      $Script:eMailRecipient = $Script:DebugUser                                    #--[ Alt destination email address during debug.
    $Script:EmailBody = "This is an automated email message.<br><br>This is a <font color=red>SIMULATED</font> Service Account password refresh:<br><br>"
}Else{
    $Script:eMailRecipient = $Script:EmailTo                                        #--[ Destination email address.
    $Script:EmailBody = "This is an automated email message.<br><br>The following Service Account passwords have been refreshed:<br><br>"
}

Function SendEmail {
    $email = New-Object System.Net.Mail.MailMessage 
    $email.From = $Script:EmailFrom
    $email.IsBodyHtml = $Script:EmailHTML
    $email.To.Add($Script:eMailRecipient)
    $email.Subject = $Script:EmailSubject + " Results"
    $email.Body = $Script:EmailBody
    $smtp = new-object Net.Mail.SmtpClient($Script:SmtpServer)
    If ($Script:SendEmail){
        $smtp.Send($email) 
        If ($Script:Console){Write-Host "`nEmail has been sent`n" -ForegroundColor Green }
    }
}

Function Encrypt-String($String, [switch]$arrayOutput){
    If ($Script:Console){Write-Host "." -NoNewline }
    $r = new-Object System.Security.Cryptography.RijndaelManaged
    $Pass = [Text.Encoding]::UTF8.GetBytes($Script:Passphrase)
    $Salt = [Text.Encoding]::UTF8.GetBytes($Script:Salt)
    $r.Key = (new-Object Security.Cryptography.PasswordDeriveBytes $Pass, $Salt, "SHA1", 5).GetBytes(32) #256/8
    $r.IV = (new-Object Security.Cryptography.SHA1Managed).ComputeHash( [Text.Encoding]::UTF8.GetBytes($Script:Init) )[0..15]
    $c = $r.CreateEncryptor()
    $ms = new-Object IO.MemoryStream
    $cs = new-Object Security.Cryptography.CryptoStream $ms,$c,"Write"
    $sw = new-Object IO.StreamWriter $cs
    $sw.Write($String)
    $sw.Close()
    $cs.Close()
    $ms.Close()
    $r.Clear()
    [byte[]]$result = $ms.ToArray()
    if($arrayOutput) {
        return $result
    } else {
        return [Convert]::ToBase64String($result)
    }
}

Function Decrypt-String($Script:Encrypted){
    if($Script:Encrypted -is [string]){
        $Script:Encrypted = [Convert]::FromBase64String($Script:Encrypted)
    }
    $r = new-Object System.Security.Cryptography.RijndaelManaged
    $Pass = [System.Text.Encoding]::UTF8.GetBytes($Script:Passphrase)
    $Salt = [System.Text.Encoding]::UTF8.GetBytes($Script:Salt)
    $r.Key = (new-Object Security.Cryptography.PasswordDeriveBytes $Pass, $Salt, "SHA1", 5).GetBytes(32) #256/8
    $r.IV = (new-Object Security.Cryptography.SHA1Managed).ComputeHash( [Text.Encoding]::UTF8.GetBytes($Script:Init) )[0..15]
    $d = $r.CreateDecryptor()
    $ms = new-Object IO.MemoryStream @(,$Script:Encrypted)
    $cs = new-Object Security.Cryptography.CryptoStream $ms,$d,"Read"
    $sr = new-Object IO.StreamReader $cs
    Write-Output $sr.ReadToEnd()
    $sr.Close()
    $cs.Close()
    $ms.Close()
    $r.Clear()
}

if (test-path "$PSScriptroot\$Script:InputFile"){
    If ($Script:Console){Write-Host "New input file found. Converting to secure text..." -ForegroundColor Magenta}
    $Script:EmailBody = "<br>New input file found. Converting to secure text...<br>"  
    If (test-path "$PSScriptroot\$Script:SecureFile"){Remove-Item "$PSScriptroot\$Script:SecureFile" -force}                   #--[ Remove the old encrypted file ]--
    $SecString = Get-Content "$PSScriptroot\$Script:InputFile" 
    ForEach ($LineItem in $SecString){
        $Encr = Encrypt-String $LineItem $Script:Passphrase
        Add-Content "$PSScriptroot\$Script:SecureFile" $Encr 
    }    
    While (test-path "$PSScriptroot\$Script:InputFile"){Remove-Item -Path "$PSScriptroot\$Script:InputFile" -Force -Confirm:$false } #-whatif
    If ($Script:Console){Write-Host "`nEncryption completed...`nSource file deleted..." -ForegroundColor Red }
    $Script:EmailBody = "<br>Encryption completed...<br>Source file deleted...<br>"
}    

If ($Script:Decode){
    if (test-path "$PSScriptroot\$Script:SecureFile"){
        $Script:Debug = $true 
        If ($Script:Console){Write-Host "Decrypting secure text to screen..." -ForegroundColor magenta }
        $SecString = Get-Content "$PSScriptroot\$Script:SecureFile"
        ForEach ($LineItem in $SecString){
            $Clear = Decrypt-String $LineItem 
            If ($Script:Console){Write-Host "-----------------------------------------" -ForegroundColor Cyan }
            If ($Script:Console){Write-Host "Decoding...." -ForegroundColor Magenta }
            If ($Script:Console){Write-Host "`tUser = " -ForegroundColor Cyan -NoNewline } 
            If ($Script:Console){Write-Host $Script:ThisUser -ForegroundColor Yellow }
            If ($Script:Console){Write-Host "`tPass = " -ForegroundColor Cyan -NoNewline }
            If ($Script:Console){Write-Host $Clear.Split(",")[1]`n -ForegroundColor Yellow  } 
        }
    }Else{
        If ($Script:Console){Write-Host "`nInput file is missing`n" -ForegroundColor Red }
          $Script:EmailBody = "<br>The Service Account Password input file was not found... Nothing to do.<br>"
    }
}

If ($Script:Enabled){
    $Script:LastSet = ""
    $Script:LastSetDate = ""
    $Script:Now = ""
    $Span = ""

    if (test-path "$PSScriptRoot\$Script:SecureFile"){
        $SecString = Get-Content "$PSScriptRoot\$Script:SecureFile" 
        ForEach ($LineItem in $SecString){
            $Clear = Decrypt-String $LineItem $Script:Passphrase       #--[ Decodes line item user and pwd ]--
            $SecString = ConvertTo-SecureString -String $Clear.Split(",")[1] -AsPlainText -Force   #--[ Converts pwd string to secure string ]--
            $Script:ThisUser = $Clear.Split(",")[0] 
            If (Get-ADUser $Script:ThisUser ){
                Try{
                    If ($Script:Debug -or $Script:Testrun){         #--[ Do nothing ]--
                        If ($Script:Console){Write-Host "`n-----------[ DEBUG MODE (Simulating Changes) ]----------------" -ForegroundColor cyan}
                        $Result = Set-ADAccountPassword -Credential $Script:Credential -Reset -NewPassword $Secstring -Identity $Script:ThisUser -PassThru -Confirm:$false -ErrorAction "Stop" -WhatIf
                        Write-host $Result -ForegroundColor Magenta
                    }Else{
                        If ($Script:Console){Write-Host "`n------------[ LIVE MODE ]----------------" -ForegroundColor Cyan }
                        If ($Script:Console){Write-Host "Updating...." -ForegroundColor Red }
                        $Result = Set-ADAccountPassword -Credential $Script:Credential -Reset -NewPassword $Secstring -Identity $Script:ThisUser -PassThru -Confirm:$false -ErrorAction "Stop"
                    }
                    $Script:EmailBody += "<br><font color=green>User <strong>"+$Script:ThisUser+"</strong> password refresh successful...</font><br>"
                }Catch{
                    $Script:EmailBody += "<br><font color=red>User <strong>"+$Script:ThisUser+"</strong> password refresh failed...</font><br>"
                    $Script:EmailBody += $_.Exception.Message
                    $Script:EmailBody += $_.Exception.ItemName
                }
            
                If ($Script:Console){Write-Host "`t User = " -ForegroundColor Cyan -NoNewline } 
                If ($Script:Console){Write-Host $Script:ThisUser -ForegroundColor Yellow }
                If ($Script:Console){Write-Host "`t Pass = " -ForegroundColor Cyan -NoNewline }
                If ($Script:Console){Write-Host $Clear.Split(",")[1] -ForegroundColor Yellow  } 
                If ($Script:Console){Write-Host "`t Hash = " -ForegroundColor Cyan -NoNewline }
                If ($Script:Console){Write-Host $LineItem -ForegroundColor Yellow  } 
            }Else{
                If ($Script:Console){Write-Host "-- User "$Script:ThisUser" was not found in Active Directory..." -ForegroundColor Red  }
                $Script:EmailBody += '"<br><font color="red">NOTICE -- User ' + $Script:ThisUser+ ' was not found in Active Directory...</font><br>'
            }
                        
            $Script:LastSet = Get-ADUser ($Script:ThisUser) -Properties PasswordLastSet 
            $Script:LastSet = ($Script:LastSet.Passwordlastset.tostring()).split(" ")[0]  
           
            $Script:Now = "{0:MM/dd/yyyy}" -f (get-date)
            $Span = NEW-TIMESPAN –Start $Script:LastSet –End $Script:Now
            
            If ($Script:Console){
                Write-Host " Last Refresh = " -NoNewline -ForegroundColor Cyan 
                Write-host "AD Password last refreshed as of"$Script:LastSet -ForegroundColor Yellow 
                Write-Host " Today = " -NoNewline -ForegroundColor Cyan 
                Write-host $Script:Now -ForegroundColor Yellow 
                Write-Host " Pwd Age = " -NoNewline -ForegroundColor Cyan 
                Write-host $Span.Days -ForegroundColor Yellow 
                Write-Host " Max Age (Days) = " -NoNewline -ForegroundColor Cyan 
                Write-host $Script:MaxDays -ForegroundColor Yellow 
                Write-Host " Password is = " -NoNewline -ForegroundColor Cyan 
            }

            If($Span.Days -le 45){
                If ($Script:Console){Write-Host "GOOD" -ForegroundColor Green }
            }else{
                If ($Script:Console){Write-host "ERROR" -ForegroundColor Red }
            }            
        }
    
    }Else{
        If ($Script:Console){Write-Host "`nInput file is missing`n" -ForegroundColor Red }
        $Script:EmailBody = "<br>The Service Account Password input file was not found... Nothing to do.<br>"
    }
}Else{
    If ($Script:Console){Write-Host "`nThis script defaults to DISABLED. It has been run DISABLED. Please re-run with ENABLED command line option set to ""TRUE"". No actions taken.`n" -ForegroundColor Red }
        $Script:EmailBody = "<br>This script defaults to DISABLED. It has been run DISABLED. Please re-run with ENABLED command line option set to ""TRUE"". No actions taken.<br>"

}

If (!($Script:Debug)){
    SendEmail 
}    

If ($Script:Console){Write-Host "Completed..." -for Red;break }

<#
<!-- Settings & Configuration File -->
<Settings>
    <General>
        <ScriptName>SvcAcctPwdRefresh.ps1</ScriptName>
        <EventlogName>PowerShell</EventlogName>
        <EventlogID>12345</EventlogID>
        <EventlogType>Information</EventlogType>
        <InputFile>svcpass.csv</InputFile>
        <SecureFile>secure.txt</SecureFile>
           <MaxDays>45</MaxDays>
    </General>
    <Email>
        <From>MonthlyReports@domain.com</From>
        <To>you@$eMailDomain,them@$eMailDomain,her@$eMailDomain</To>
        <Subject>Monthly Service Account PWD Update</Subject>
        <Domain>domain.com</Domain>
        <HTML>$true</HTML>
        <SmtpServer>10.1.1.50</SmtpServer>
        <DebugUser>you@domain.com</DebugUser>
        <Enable>$True</Enable>
    </Email>
    <Credentials>
    <UserName>mydomain\serviceaccount</UserName>
        <Password>encrypted-password-goes-here</Password>
        <Passphrase>OOGA-BOOGA</Passphrase>
        <Salt>P455W0RDs Are A Pain!</Salt>
        <Init>Yet another key</Init>
    </Credentials>
</Settings>
#>