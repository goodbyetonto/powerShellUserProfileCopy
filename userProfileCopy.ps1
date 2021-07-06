### Prompt for input: Network or Local transfer? ###
$Transfer_Type = Read-Host "Type 'local' if you are executing script from user's computer. Type 'network' if you are executing remotely"

### Robocopy Staging Log Path ###
$RoboStagingLog = "\\nasprod\helpdesk\userBups\bupLogs\staging_backup"
### Robocopy Final Log Path ###
$RoboFinalLog = "\\nasprod\helpdesk\userBups\bupLogs\final_backup"
### Script Transcript (ie. error handling) ###
$Transcript = "\\nasprod\helpdesk\userBups\scriptTranscripts"

### assign variable values for either local/network initiated script ###
if($Transfer_Type -eq 'network')
{
    ### Prompt for input of hostname ###
    $Hostname = Read-Host "Please enter the hostname of the computer"
    ### Retrieve user/profile name ###
    $Get_User = Read-Host "Please enter the username of they whose data you would like to copy"
    ### User Profile Path for running over the network ###
    $User_Profile = "\\$Hostname\c$\Users\$Get_User"
} 
else 
{
    ### Hostname
    $Hostname = hostname
    ### User/profile name ###
    $Get_User = Read-Host "Please enter the username of they whose data you would like to copy"
    ### User Profile Path ###
    $User_Profile = "C:\Users\$Get_User"
}

### Destination Path ###
$Destination = "\\nasprod\helpdesk\userBups\$Hostname\$Get_User"

### Time-Stamp ###
$DateTime = Get-Date -Format 'yyyy-MM-dd HH-mm-ss'

### Chrome Bookmarks ###
$Chrome_Bm = "$User_Profile\AppData\Local\Google\Chrome\User Data\Default\Bookmarks"

### Firefox Profile ###
$Firefox_Prof = "$User_Profile\AppData\Roaming\Mozilla\Firefox\Profiles"

### Folders to exclude ###
$Excludes_Folder = 
    '.dotnet',
    '.vscode',
    'AppData',
    'Application Data', 
    'Cookies', 
    'IntelGraphicsProfiles',
    'Local Settings', 
    'MicrosoftEdgeBackups', 
    'Nethood', 
    'OneDrive', 
    'PrintHood', 
    'Recent', 
    'SendTo', 
    'source', 
    'Start Menu', 
    'Templates' 

##### Excluded folder pathways for running script over network/locally #####

### Folder Paths for Exclusion ###
$Exclude = @()

Foreach($Folder in $Excludes_Folder)
{
    $Exclude += ,"$User_Profile\$Folder"
}

### Files to Exclude when using 'Robocopy' ###
$Excludes_Files

##### ROBOCOPY W/STATUS BAR #####
function Copy-WithProgress {
    [CmdletBinding()]
    param (
            [Parameter(Mandatory = $true)]
            [string] $User_Profile
        , [Parameter(Mandatory = $true)]
            [string] $Destination
        , [int] $Gap = 0 
        , [int] $ReportGap = 2000
    )
    ### Define regular expression that will gather number of bytes copied ###
    $RegexBytes = '(?<=\s+)\d+(?=\s+)' #'(?<=\s+New File\s+)\d+(?=\s+)'

    ### Region Robocopy params ###

    # MIR = Mirror mode
    # XA:SH = Excludes Hidden System Files 
    # XD  = Excludes Folders meeting the criteria 
    # XF  = Exludes these file extensions 
    # XJD = Exlude all junction points
    # R   = Number of retries to copy file that is currently in use
    # W   = Wait time in seconds between retries
    # MT  = Number of threads to utilize for multi-thread data copying
    # NP  = Don't show progress percentage in log
    # NC  = Don't log file classes (existing, new file, etc.)
    # BYTES = Show file sizes in bytes
    # NJH = Do not display robocopy job header (JH)
    # NJS = Do not display robocopy job summary (JS)
    # TEE = Display log in stdout AND in target log file

    ### Assign Robocopy params to string variable ###
    $CommonRobocopyParams = "/MIR /XA:SH /XD $Excludes_Folder /XJD /R:5 /W:15 /MT:13 /Z /NP /NDL /NC /BYTES /NJH /NJS"

    ### Region Robocopy Staging ###
    Write-Verbose -Message 'Analyzing robocopy job ...'
    $StagingLogPath = '{0}\{1}' -f $RoboStagingLog, $Hostname + "_$Get_User" +"_$DateTime" 

    $StagingArgumentList = '"{0}" "{1}" /LOG:"{2}" /L {3}' -f $User_Profile, $Destination, $StagingLogPath, $CommonRobocopyParams
    Write-Verbose -Message ('Staging arguments: {0}' -f $StagingArgumentList)
    Start-Process -Wait -FilePath robocopy.exe -ArgumentList $StagingArgumentList -NoNewWindow
    ### Get the total number of files that will be copied ###
    $StagingContent = Get-Content -Path $StagingLogPath
    $TotalFileCount = $StagingContent.Count - 1

    ### Get the total number of bytes to be copied ###
    [RegEx]::Matches(($StagingContent -join "`n"), $RegexBytes) | ForEach-Object { $BytesTotal = 0; } { $BytesTotal += $_.Value; };
    Write-Verbose -Message ('Total bytes to be copied: {0}' -f $BytesTotal)

    ### Region Start Robocopy ###
    $RobocopyLogPath = '{0}\{1}' -f $RoboFinalLog, $Hostname + "_$Get_User" + "_$DateTime"
    $ArgumentList = '"{0}" "{1}" /LOG:"{2}" /ipg:{3} {4}' -f $User_Profile, $Destination, $RobocopyLogPath, $Gap, $CommonRobocopyParams
    Write-Verbose -Message ('Beginning the robocopy process with arguments: {0}' -f $ArgumentList)
    $Robocopy = Start-Process -FilePath robocopy.exe -ArgumentList $ArgumentList -Verbose -PassThru -NoNewWindow
    Start-Sleep -Milliseconds 100

    ### Region Progress bar loop ###
    while (!$Robocopy.HasExited) {
        Start-Sleep -Milliseconds $ReportGap
        $BytesCopied = 0
        $LogContent = Get-Content -Path $RobocopyLogPath
        $BytesCopied = [Regex]::Matches($LogContent, $RegexBytes) | ForEach-Object -Process { $BytesCopied += $_.Value; } -End { $BytesCopied; };
        $CopiedFileCount = $LogContent.Count - 1
        Write-Verbose -Message ('Bytes copied: {0}' -f $BytesCopied)
        Write-Verbose -Message ('Files copied: {0}' -f $LogContent.Count)
        $Percentage = 0
        if ($BytesCopied -gt 0) {
           $Percentage = (($BytesCopied/$BytesTotal)*100)
        }
        Write-Progress -Activity Robocopy -Status ("Copied {0} of {1} files; Copied {2} of {3} bytes" -f $CopiedFileCount, $TotalFileCount, $BytesCopied, $BytesTotal) -PercentComplete $Percentage
    }

    ### Region function output ###
    [PSCustomObject]@{
        BytesCopied = $BytesCopied
        FilesCopied = $CopiedFileCount
    };
}

### Start Powershell Transcript Recording ###
Start-Transcript -Path ('{0}\{1}\{2}\{3}' -f $Transcript, $Get_User, $Hostname, $DateTime) -NoClobber
### Call Copy-WithProgress function(Robocopy) ###
Copy-WithProgress $User_Profile $Destination -Verbose
### Get Chrome Bookmark's file and copy to destination folder ###
Copy-Item -Path "$Chrome_Bm " -Destination $Destination
### Get and copy Firefox Profile to destination folder ###
Copy-Item -Path "$Firefox_Prof" -Destination $Destination -Recurse;
### Get Printers and create and save to destination folder ###
Get-Printer -ComputerName $Hostname | Out-File -FilePath "$Destination\printers";
### Get list of installed apps and save to destination folder ###
Get-AppxPackage -User "csusm\$Get_User" -PackageTypeFilter Main | Select-Object Name | Out-File -FilePath "$Destination\apps"
### Stop Powershell Transcript Recording ###
Stop-Transcript
