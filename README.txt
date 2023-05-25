# SvcAcctPwdRefresh
Will refresh a list of service account passwords from an encrypted file.  The script can create the encrypted file and also decode it.

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
