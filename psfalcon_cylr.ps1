#Requires -Version 5.1
using module @{ ModuleName = 'PSFalcon'; ModuleVersion = '2.0' }

# Retrieve this information from Crowdstrike API
# -Cloud should be defined as your location (e.g. us-1, us-2, etc)
Request-FalconToken -ClientId XXXXX -ClientSecret XXXXX -Cloud XX-X

#$VerbosePreference = 'Continue'

[Environment]::CurrentDirectory = Get-Location

#Multiple hosts can be added to a hosts.txt file
$reader = [System.IO.File]::OpenText(".\hosts.txt")

$offlineHosts = @()

while($null -ne ($line = $reader.ReadLine())) {

        $lineUpper = $line.ToUpper()
        Write-Host Executing on $lineUpper
        $HostId = Get-FalconHost -Filter "hostname:'$lineUpper'" -Sort last_seen.desc -Limit 1
        $startSession = Start-FalconSession -HostId $HostId -ErrorAction SilentlyContinue

        function Upload-CyLR {
                Write-Host 'Uploading CyLR...'
                Invoke-FalconRTR -Command put -Arguments 'CyLR.exe' -HostIds $HostId
        Write-Host 'Upload complete.'
        }

        function Run-CyLR {
                Write-Host 'Running CyLR...'
                # User a new sftp password every time. Change after each use just to be safe. Exclude [] for the data below.
                Invoke-FalconRTR -Command runscript -Arguments '-Raw=```Start-Process C:\CyLR.exe -s [SFTP-SERVER-ADDRESS] -u [SFTP-USER] -p [SFTP-PASSWORD] -Verb runAs```' -HostIds $HostId
        }


        function Cleanup-CyLR {
                Write-Host 'Cleaning up - Deleting log file'
                Invoke-FalconRTR -Command rm -Arguments 'C:\CyLR.log' -HostIds $HostId
        }


    #######################
    ## BEGIN THE PROCESS ##
    #######################

        Write-Host -NoNewline "Connecting to $lineUpper... "
        if ($startSession -like "*session_id*"){
                Write-Host "Connected."
                Upload-CyLR
                Run-CyLR
                
                ### CREATE WHILE LOOP. IF CYLR IS DONE RUNNING, DEFINE A AS 12 TO PROCEED. ELSE, WAIT ANOTHER 2 MINUTES AND TRY AGAIN. EXPIRE AFTER 10 FAILED ATTEMPTS ###
                $a = 0
                while ($a -le 10) {
                        $cylr = Invoke-FalconRTR -Command rm -Arguments 'C:\CyLR.exe' -HostIds $HostId
                        if ([string]::IsNullOrEmpty($cylr.stderr)){
                Write-Host 'CyLR is complete.'
                $a = 12
                        } else {
                                Write-Host -NoNewline "."
                                Start-Sleep -Seconds 120
                                $a++
                        }
                }
                if ($a -eq 11) {
                        Write-Host 'This is taking longer than expected (20min+). Please check this file again later.'
                } elseif ($a -eq 12) {
                        Cleanup-CyLR
                }

        } else {
                Write-Host "$lineUpper is offline."
                #Add hostname to list to print at the end of this program.
        $offlineHosts +=$lineUpper
        }

}
if ($offlineHosts.count -eq 0){
    ### REPLACE XXX WITH LOCATION THAT FILES WERE UPLOADED TO ###
    Write-Host "Complete. Please check the 'XXXXX' folder on SFTP server for any uploaded files."
} else {
    Write-Host "The following hosts could not be reached:"
    Write-Host "-----------------------------------------"
    $offlineHosts
}

