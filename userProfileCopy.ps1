do {
    # Prompt for input: Network or Local? 
    $TransferType = Read-Host "TYPE 'local' IF YOU ARE EXECUTING SCRIPT FROM USER'S COMPUTER. TYPE 'network' IF YOU ARE EXECUTING SCRIPT REMOTELY"
    # Insert line break in terminal 
    Write-Host "`n"
    # Check to make sure user input matches either 'local' or 'network' 
} until (($TransferType -match 'local' -or ($TransferType -match 'network')))

# Assign variable values for either local/network initiated script 
if ($TransferType -eq 'network') {
    # Prompt for input of hostname 
    do {
        $Hostname = Read-Host "ENTER THE HOSTNAME OF THE COMPUTER PROFILE WILL BE COPIED FROM"
        Write-Host "`n"
        $Confirm = Read-Host "CONFIRM HOSTNAME"    
        Write-Host "`n"    
    } until ($Hostname -eq $Confirm)
    # Retrieve user/profile name 
    do {
        $GetUser = Read-Host "ENTER THE USERNAME OF THE PROFILE YOU WOULD LIKE TO COPY"
        Write-Host "`n"
        $Confirm = Read-Host "CONFIRM USERNAME"
        Write-Host "`n"
    } until ($GetUser -eq $Confirm)
    # User Profile Path for running over the network 
    $UserProfile = "\\$Hostname\c$\Users\$GetUser"
} 
else {
    # User Profile Path 
    $Hostname = hostname
    $GetUser = $env:username
    $UserProfile = "C:\Users\$GetUser" 
}

# Destination Path 
$Destination = { SUPPLY YOUR NETWORK FOLDER PATH HERE }

# Time-Stamp 
$DateTime = Get-Date -Format 'yyyy-MM-dd HH-mm-ss'

# Chrome Bookmarks 
$ChromeBm = "$UserProfile\AppData\Local\Google\Chrome\User Data\Default\Bookmarks"

# Firefox Profile 
$FirefoxProf = "$UserProfile\AppData\Roaming\Mozilla\Firefox\Profiles\*" 

# Network Printer Array 
$PrintArray = @(Get-WMIObject Win32_Printer -ComputerName $Hostname | Where-Object { $_.Name -like "*\\*" } | Select-Object -ExpandProperty name)

# Network Folder Array 
$NetFolders = @(Get-WMIObject Win32_MappedLogicalDisk -ComputerName $Hostname | Where-Object { $_.ProviderName -notlike " {PLACE ANY DEFAULT MAPPED FILE SHARES HERE} " } | Select-Object -ExpandProperty ProviderName)

# Folders to exclude 
$ExcludesFolder = 
".dotnet",
".vscode",
"AppData",
"Application Data", 
"{PLACE SHAREPOINT FILE LEAF NAME HERE}",
"Cookies", 
"IntelGraphicsProfiles",
"Local Settings", 
"MicrosoftEdgeBackups", 
"Nethood", 
"{PLACE ONEDRIVE FILE LEAF NAME HERE"}, 
"SendTo", 
"source",
"Start Menu", 
"Templates" 

# Excluded Folder Path Aray 
$Exclude = @()

# Loop through $ExcludesFolder and append each leaf to $UserProfile path
Foreach ($Folder in $ExcludesFolder) {
    $Exclude += , "$UserProfile\$Folder"
}

# Join $Exclude strings into seperate strings space delimited
$Exclude = '"' + ($Exclude -join '" "') + '"'

# Files to Exclude when using 'Robocopy' 
$ExcludesFiles

# Robocopy Staging Log Path 
$RoboStagingLog = "\\{PARENT FOLDER NAME HERE}\userBups\bupLogs\staging_backup"
# Robocopy Final Log Path 
$RoboFinalLog = "\\{PARENT FOLDER NAME HERE}\userBups\bupLogs\final_backup"
# Script Transcript (ie. error handling) 
$Transcript = "\\{PARENT FOLDER NAME HERE}\userBups\scriptTranscripts"

# Copy-WithProgress Function by Trevor Sullivan (https://stackoverflow.com/questions/13883404/custom-robocopy-progress-bar-in-powershell) w/some changes of my own
function Copy-WithProgress {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $UserProfile
        , [Parameter(Mandatory = $true)]
        [string] $Destination
        , [int] $Gap = 0 
        , [int] $ReportGap = 2000
    )
    # regular expression that will gather number of bytes copied 
    $RegexBytes = '(?<=\s+)\d+(?=\s+)' 

    # ROBOCOPY ARGUMENT DEFINITIONS 

    # MIR = Mirrors source directory tree
    # B   = Backup mode, overrides folder/file permissions
    # COPYALL = Copies all file information (equivalent to /copy:DATSOU)
    # COMPRESS = Requests network compression during file transfer, if applicable
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

    # Assign Robocopy params to string variable 
    $CommonRobocopyParams = '/MIR /B /COMPRESS /XA:SH /XD ' + $Exclude + ' /XJD /R:5 /W:15 /MT:40 /Z /NP /NDL /NC /BYTES /NJH /NJS' 

    # Region Robocopy Staging 
    Write-Verbose -Message 'Analyzing robocopy job ...'
    Write-Host "`n"
    # Staging log filepath 
    $StagingLogPath = '{0}\{1}' -f $RoboStagingLog, $Hostname + "_$GetUser" + "_$DateTime" 

    # Robocopy Staging arguments (ie. source path, destination path, staging log path, robocopy arguments)
    $StagingArgumentList = '"{0}" "{1}" /LOG:"{2}" /L {3}' -f $UserProfile, $Destination, $StagingLogPath, $CommonRobocopyParams
    Write-Verbose -Message ('Staging arguments: {0}' -f $StagingArgumentList)
    Write-Host "`n"
    Start-Process -Wait -FilePath robocopy.exe -ArgumentList $StagingArgumentList -NoNewWindow
    # Get the total number of files that will be copied 
    $StagingContent = Get-Content -Path $StagingLogPath
    $TotalFileCount = $StagingContent.Count 

    # Get the total number of bytes to be copied 
    [RegEx]::Matches(($StagingContent -join "`n"), $RegexBytes) | ForEach-Object { $BytesTotal = 0; } { $BytesTotal += $_.Value; };
    Write-Verbose -Message ('Total bytes to be copied: {0}' -f $BytesTotal)
    Write-Host "`n"

    # Region Start Robocopy 
    $RobocopyLogPath = '{0}\{1}' -f $RoboFinalLog, $Hostname + "_$GetUser" + "_$DateTime"
    $ArgumentList = '"{0}" "{1}" /LOG:"{2}" /ipg:{3} {4}' -f $UserProfile, $Destination, $RobocopyLogPath, $Gap, $CommonRobocopyParams
    Write-Verbose -Message ('Beginning the robocopy process with arguments: {0}' -f $ArgumentList)
    $Robocopy = Start-Process -FilePath robocopy.exe -ArgumentList $ArgumentList -Verbose -PassThru -NoNewWindow
    Start-Sleep -Milliseconds 100

    # Region Progress bar loop 
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
            $Percentage = (($BytesCopied / $BytesTotal) * 100)
        }
        Write-Progress -Activity Robocopy -Status ("Copied {0} of {1} files; Copied {2} of {3} bytes" -f $CopiedFileCount, $TotalFileCount, $BytesCopied, $BytesTotal) -PercentComplete $Percentage
    }

    # Region function output 
    [PSCustomObject]@{
        BytesCopied = $BytesCopied
        FilesCopied = $CopiedFileCount
    };
}

# Start Powershell Transcript Recording 
Start-Transcript -Path ('{0}\{1}\{2}\{3}' -f $Transcript, $GetUser, $Hostname, $DateTime + "_copy") -NoClobber

# Call Copy-WithProgress function(Robocopy) 
Copy-WithProgress $UserProfile $Destination -Verbose
Start-Sleep -s 5

# Get Chrome Bookmark's file and copy to destination folder 
Write-Host "`n"
Write-Verbose -Message "Copying Chrome Bookmarks to $Destination" -Verbose
Write-Host "`n"
# Copy Chrome bookmarks to destination path
Copy-Item -Path $ChromeBm  -Destination $Destination

# Create Firefox Folder and copy Firefox Profile to destination folder 
Write-Verbose -Message "Creating folder for Firefox Profile in $Destination" -Verbose
Write-Host "`n"
# Create new directory in destination path for Firefox profiles 
New-Item -Path "$Destination" -Name "Firefox" -ItemType "directory"
Write-Verbose -Message "Copying Firefox Profile to $Destination\Firefox" -Verbose
Write-Host "`n"
# Copy Firefox profiles to destination path
Copy-Item -Path "$FirefoxProf" -Destination "$Destination\Firefox" -Recurse;

# Get Network Printers and create and save to destination folder #
Write-Verbose -Message "Creating network printer list to $Destination\printers" -Verbose
Write-Host "`n"
$PrintArray | Out-File -FilePath "$Destination\printers";

# Get list of installed apps and save to destination folder #
Write-Verbose -Message "Creating installed application text file to $Destination\apps" -Verbose
Write-Host "`n" 
Get-AppxPackage -User "{DOMAIN NAME HERE}\$GetUser" -PackageTypeFilter Main | Select-Object Name | Out-File -FilePath "$Destination\apps";

# Get Network folders and create and save to destination folder #
Write-Verbose -Message "Creating network folders text file to $Destination\netFolders" -Verbose
Write-Host "`n"
$NetFolders | Out-File -FilePath "$Destination\netFolders";

# Stop Powershell Transcript Recording #
Stop-Transcript
