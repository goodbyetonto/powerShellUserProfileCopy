### Prompt for input: Network or Local transfer? ###
$Transfer_Type = Read-Host "Type 'local' if you are executing script from user's computer. Type 'network' if you are executing remotely"

#assign source values based on whether migration is being initiated locally or over the network
if($Transfer_Type -eq 'network')
{
    ### Prompt for input of hostname ###
    $Hostname = Read-Host "Please enter the hostname of the computer"
    $User_Profile = Read-Host "Please enter the username of they whose data you would like to copy"
    ### User Profile Path for running over the network ###
    $User_Profile_Net = "\\$Hostname\c$\Users\$User_Profile"
} 
else 
{
    ### Retrieve user/profile name ###
    $Get_User = $env:username
    ### User Profile Path ###
    $User_Profile = "C:\Users\$Get_User"
}

### Destination Path ###
$Destination = "\\nasprod\helpdesk\userBups\$Get_User"

### Robocopy Staging Log Path ###
$RoboStagingLog = "\\nasprod\helpdesk\userBups\bupLogs\staging"

### Robocopy Final Log Path ###
$RoboFinalLog = "\\nasprod\helpdesk\userBups\bupLogs\final"

##### Browsing Bookmark Paths #####

### Chrome Bookmarks Local###
$Chrome_Bm_Local = "$User_Profile\AppData\Local\Google\Chrome\User Data\Default\Bookmarks"

### Chrome Bookmarks Net ###
$Chrome_Bm_Net = "$User_Profile_Net\AppData\Local\Google\Chrome\User Data\Default\Bookmarks"

### Firefox Profile Local ###
$Firefox_Prof = "$User_Profile\AppData\Roaming\Mozilla\Firefox\Profiles"

### Firefox Profile Net ###
$Firefox_Prof_Net = "$User_Profile_Net\AppData\Roaming\Mozilla\Firefox\Profiles"

### Folders to exclude ###
$Excludes_Folder = 
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
    'Start Menu', 
    'Templates' 

##### Excluded folder pathways for running script over network/locally #####

### Local Folder Paths for Exclusion ###
$Exclude_Local = @()

Foreach($Folder in $Excludes_Folder)
{
    $Exclude_Local += ,"$User_Profile\$folder"
}

### Network Folder Paths for Exclusion ###
$Exclude_Net = @()

Foreach($Folder in $Excludes_Folder)
{
    $Exclude_Net += ,"$User_Profile_Net\$folder"
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
    # Define regular expression that will gather number of bytes copied
    $RegexBytes = '(?<=\s+)\d+(?=\s+)';

    #region Robocopy params
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
    # BYTES = Show file sizes in bytesY
    # NJH = Do not display robocopy job header (JH)
    # NJS = Do not display robocopy job summary (JS)
    # TEE = Display log in stdout AND in target log file
    $CommonRobocopyParams = "/MIR /XA:SH /XD $Excludes_Folder /XJD /R:5 /W:15 /MT:12 /Z /NP /NDL /NC /BYTES /NJH /NJS";
    #endregion Robocopy params

    #region Robocopy Staging
    Write-Verbose -Message 'Analyzing robocopy job ...';
    $StagingLogPath = '{0}\{1}' -f $RoboStagingLog, $Get_User + '_' + (Get-Date -Format 'yyyy-MM-dd HH-mm-ss') + '_staging';

    $StagingArgumentList = '"{0}" "{1}" /LOG:"{2}" /L {3}' -f $User_Profile, $Destination, $StagingLogPath, $CommonRobocopyParams;
    Write-Verbose -Message ('Staging arguments: {0}' -f $StagingArgumentList);
    Start-Process -Wait -FilePath robocopy.exe -ArgumentList $StagingArgumentList -NoNewWindow;
    # Get the total number of files that will be copied
    $StagingContent = Get-Content -Path $StagingLogPath;
    $TotalFileCount = $StagingContent.Count - 1;

    # Get the total number of bytes to be copied
    [RegEx]::Matches(($StagingContent -join "`n"), $RegexBytes) | % { $BytesTotal = 0; } { $BytesTotal += $_.Value; };
    Write-Verbose -Message ('Total bytes to be copied: {0}' -f $BytesTotal);
    #endregion Robocopy Staging

    #Region Start Robocopy
    # Begin the robocopy process
    $RobocopyLogPath = '{0}\{1}' -f $RoboFinalLog, $Get_User + '_' + (Get-Date -Format 'yyyy-MM-dd HH-mm-ss') + '_final';
    $ArgumentList = '"{0}" "{1}" /LOG:"{2}" /ipg:{3} {4}' -f $User_Profile, $Destination, $RobocopyLogPath, $Gap, $CommonRobocopyParams;
    Write-Verbose -Message ('Beginning the robocopy process with arguments: {0}' -f $ArgumentList);
    $Robocopy = Start-Process -FilePath robocopy.exe -ArgumentList $ArgumentList -Verbose -PassThru -NoNewWindow;
    Start-Sleep -Milliseconds 100;
    #endregion Start Robocopy

    #region Progress bar loop
    while (!$Robocopy.HasExited) {
        Start-Sleep -Milliseconds $ReportGap;
        $BytesCopied = 0;
        $LogContent = Get-Content -Path $RobocopyLogPath;
        $BytesCopied = [Regex]::Matches($LogContent, $RegexBytes) | ForEach-Object -Process { $BytesCopied += $_.Value; } -End { $BytesCopied; };
        $CopiedFileCount = $LogContent.Count - 1;
        Write-Verbose -Message ('Bytes copied: {0}' -f $BytesCopied);
        Write-Verbose -Message ('Files copied: {0}' -f $LogContent.Count);
        $Percentage = 0;
        if ($BytesCopied -gt 0) {
           $Percentage = (($BytesCopied/$BytesTotal)*100)
        }
        Write-Progress -Activity Robocopy -Status ("Copied {0} of {1} files; Copied {2} of {3} bytes" -f $CopiedFileCount, $TotalFileCount, $BytesCopied, $BytesTotal) -PercentComplete $Percentage
    }
    #endregion Progress loop

    #region Function output
    [PSCustomObject]@{
        BytesCopied = $BytesCopied;
        FilesCopied = $CopiedFileCount;
    };
    #endregion Function output
}

### Call the Copy-WithProgress Function for either local or network conditions ###
if($Transfer_Type -eq 'local'){
    Copy-WithProgress $User_Profile $Destination -Verbose;
    Get-Item -Path $Chrome_Bm_Local -Force | Copy-Item -Destination $Destination; 
    Get-Item -Path $Firefox_Prof_Local -Force | Copy-Item -Destination $Destination -Recurse;
    Get-Printer | Out-File -FilePath "$Destination\printers"; 
    Get-AppxPackage -User "csusm\$Get_User" -PackageTypeFilter Main | Select Name | Out-File -FilePath "$Destination\apps";
} else {
    Copy-WithProgress $User_Profile_Net $Destination -Verbose; 
    Get-Item -Path $Chrome_Bm_Net -Force | Copy-Item -Destination $Destination; 
    Get-Item -Path $Firefox_Prof_Net -Force | Copy-Item -Destination $Destination -Recurse;
    Get-Printer -ComputerName $Hostname | Out-File -FilePath "$Destination\printers"; 
}



