### Prompt for input: Network or Local transfer? ###
$Transfer_Type = Read-Host "Type 'local' if you are executing script from user's computer. Type 'network' if you are executing remotely"

#assign source values based on whether migration is being initiated locally or over the network
if ($Transfer_Type -eq 'network') {
    ### Prompt for input of hostname ###
    $Hostname = Read-Host "Please enter the hostname of the computer"
    ### Prompt for input of the username of the peroson whose data is being migrated ###
    $Get_User = Read-Host "Please enter the username of the Windows profile you are transferring data to"
    ### Source Path on \\nasprod ###
    $Source_Path = "\\nasprod\helpdesk\userBups\$Hostname\$Get_User"
    ### User Profile Path for running over the network ###
    $User_Profile = "\\$Hostname\c$\Users\gtrask-la"
} 
else {
    ### Get Hostname ###
    $Hostname = Read-Host "Please enter the hostname of the computer"
    ### Retrieve user/profile name ###
    $Get_User = Read-Host "Please enter the username of the Windows profile you are transferring data to"
    ### Source Path on \\nasprod ###
    $Source_Path = "\\nasprod\helpdesk\userBups\$Hostname\$Get_User"
    ### User Profile Path for running script locally ###
    $User_Profile = "C:\Users\gtrask-la"
}

### Source Path Array ###
$Source_Paths = Get-ChildItem $Source_Path | ForEach-Object{$_.FullName}

### Destination Path Array ### 
$Destination_Paths = Get-ChildItem $User_Profile | ForEach-Object{$_.FullName}

### Time-Stamp ###
$DateTime = Get-Date -Format 'yyyy-MM-dd HH-mm-ss'

### Chrome Bookmarks Source ###
$Chrome_Bm = "$Source_Path\Bookmarks"

### Chrome Bookmarks Destination ###
$Chrome_Bm_Dest = "$User_Profile\AppData\Local\Google\Chrome\User Data\Default"

### Firefox Profile Source ###
$Firefox_Prof = "$Source_Path\Profiles"

### Firefox Profile Destination ###
$Firefox_Prof_Dest = "$User_Profile\AppData\Roaming\Mozilla\Firefox"

### Network Printer Array ###
$Printers = Get-Content "$Source_Path\printers"

### Robocopy Migrate-Data Staging Log Path ###
$RoboStagingLog = "\\nasprod\helpdesk\userBups\bupLogs\staging_migrate"

### Robocopy Migrate-Data Final Log Path ###
$RoboFinalLog = "\\nasprod\helpdesk\userBups\bupLogs\final_migrate"

### Script Transcript (ie. error handling) ###
$Transcript = "\\nasprod\helpdesk\userBups\scriptTranscripts"

    
##### ROBOCOPY W/STATUS BAR #####
function Copy-WithProgress {
    [CmdletBinding()]
    param (
          [Parameter(Mandatory = $true)]
        [string] $Source_Folder
        , [Parameter(Mandatory = $true)]
        [string] $Destination   
        , [Parameter(Mandatory = $true)]
        [string] $RoboParams
        , [Parameter(Mandatory = $true)]
        [string] $Source_Leaf
        , [int] $Gap = 0 
        , [int] $ReportGap = 4000
    )
    ### Define regular expression that will gather number of bytes copied ###
    $RegexBytes = '(?<=\s+)\d+(?=\s+)'

    #region Robocopy params
    # MIR = Mirror mode
    # XA:SH = Excludes Hidden System Files 
    # XD  = Excludes Folders meeting the criteria 
    # XF  = Exludes these file extensions 
    # R   = Number of retries to copy file that is currently in use
    # W   = Wait time in seconds between retries
    # MT  = Number of threads to utilize for multi-thread data copying
    # Z   = Will retry a file copy if network connectivity drops or fails
    # NP  = Don't show progress percentage in log
    # NC  = Don't log file classes (existing, new file, etc.)
    # BYTES = Show file sizes in bytes
    # NJH = Do not display robocopy job header (JH)
    # NJS = Do not display robocopy job summary (JS)
    # TEE = Display log in stdout AND in target log file

    ### Robocopy Staging ###
    Write-Verbose -Message 'Analyzing robocopy job ...'
    `n
    `n
    `n
    $StagingLogPath = '{0}\{1}' -f $RoboStagingLog, $Hostname + "_$Get_User" + "_$Source_Tree" + "_$DateTime"

    $StagingArgumentList = '"{0}" "{1}" /LOG:"{2}" /L {3}' -f $Source_Folder, $Destination, $StagingLogPath, $CommonRobocopyParams
    Write-Verbose -Message ('Staging arguments: {0}' -f $StagingArgumentList)
    `n
    `n
    `n
    Start-Process -Wait -FilePath robocopy.exe -ArgumentList $StagingArgumentList -NoNewWindow
    ### Get the total number of files that will be copied ###
    $StagingContent = Get-Content -Path $StagingLogPath
    $TotalFileCount = $StagingContent.Count - 1

    ### Get the total number of bytes to be copied ###
    [RegEx]::Matches(($StagingContent -join "`n"), $RegexBytes) | ForEach-Object { $BytesTotal = 0; } { $BytesTotal += $_.Value; }
    Write-Verbose -Message ('Total bytes to be copied: {0}' -f $BytesTotal)

    ### Begin the robocopy process ###
    $RobocopyLogPath = '{0}\{1}' -f $RoboFinalLog, $Hostname + "_$Get_User" + "_$Source_Tree" + "_$DateTime" 
    $ArgumentList = '"{0}" "{1}" /LOG:"{2}" /ipg:{3} {4}' -f $Source_Folder, $Destination, $RobocopyLogPath, $Gap, $CommonRobocopyParams
    Write-Verbose -Message ('Beginning the robocopy process with arguments: {0}' -f $ArgumentList)
    `n
    `n
    `n
    $Robocopy = Start-Process -FilePath robocopy.exe -ArgumentList $ArgumentList -Verbose -PassThru -NoNewWindow
    Start-Sleep -Milliseconds 100

    ### Progress bar loop ###
    while (!$Robocopy.HasExited) {
        Start-Sleep -Milliseconds $ReportGap
        $BytesCopied = 0
        $LogContent = Get-Content -Path $RobocopyLogPath
        $BytesCopied = [Regex]::Matches($LogContent, $RegexBytes) | ForEach-Object -Process { $BytesCopied += $_.Value; } -End { $BytesCopied; }
        $CopiedFileCount = $LogContent.Count - 1
        Write-Verbose -Message ('Bytes copied: {0}' -f $BytesCopied)
        Write-Verbose -Message ('Files copied: {0}' -f $LogContent.Count)
        $Percentage = 0
        if ($BytesCopied -gt 0) {
            $Percentage = (($BytesCopied / $BytesTotal) * 100)
        }
        Write-Progress -Activity Robocopy -Status ("Copied {0} of {1} files; Copied {2} of {3} bytes" -f $CopiedFileCount, $TotalFileCount, $BytesCopied, $BytesTotal) -PercentComplete $Percentage
    }

    ### Function output ###
    [PSCustomObject]@{
        BytesCopied = $BytesCopied;
        FilesCopied = $CopiedFileCount;
    };
}

### Start Powershell Transcript Recording ###
Start-Transcript -Path ('{0}\{1}\{2}\{3}' -f $Transcript, $Get_User, $Hostname, $DateTime + "_migrate") -NoClobber

### Call the Copy-WithProgress Function ###
foreach($Source in $Source_Paths)
{
    $Source_Leaf = Split-Path -Path $Source -Leaf 
    foreach($Destination in $Destination_Paths)
    {
        $Destination_Leaf = Split-Path -Path $Destination -Leaf 
        if($Source_Leaf -eq $Destination_Leaf)
        {
            $CommonRobocopyParams = "/MIR /R:5 /W:15 /COPY:DAT /MT:13 /Z /NP /NDL /NC /BYTES /NJH"
            Copy-WithProgress $Source $Destination $CommonRobocopyParams $Source_Leaf -Verbose
        }    
        else 
        {
            $CommonRobocopyParams = "/E /R:5 /W:15 /COPY:DAT /MT:13 /Z /NP /NDL /NC /BYTES /NJH"
            Copy-WithProgress $Source $Destination $CommonRobocopyParams $Source_Leaf -Verbose
        }
    } 
}

### Open Chrome (If user hasn't opened Chrome, there will be no Destination folder) ###
Start-Process -FilePath "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
Start-Sleep -Milliseconds 3000 
### Copy Chrome Bookmarks to destination ###
Copy-Item $Chrome_Bm $Chrome_Bm_Dest
### Open Firefox ### 
Start-Process -FilePath "C:\Program Files (x86)\Mozilla Firefox\firefox.exe"
### Copy Firefox Profile folder to destination ###
Copy-Item $Firefox_Prof $Firefox_Prof_Dest -Verbose
### Loop through network printer array and add each to user profile ###
for($i=3; $i -eq $Printers.Length; $i++)
{
    ### Add network printer & wait to continue to next printer ###
    Add-Printer -ConnectionName $Printers[$i] | Out-Null
    Write-Verbose -Message ('Adding Network Printer: {0} ' -f $Printers[$i]) -Verbose
}
### Stop Powershell Transcript Recording ###
Stop-Transcript
