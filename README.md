# powerShellUserProfileCopy

Having worked in a Helpdesk setting for the last several years, I wanted to automate much of the tedious tasks we do during PC refreshes. Copying a user's files to an external USB drive and then back to their new PC can take quite some time. Relying on a user to use OneDrive in a way that ensures they are capturing all their data is not reasonable. Users tend to overlook backing up browsing data, network printers, fileshares, etc. In addition, it is not very secure to keep user files on external drives, and so I wanted to also build a solution that keeps their files on a local network storage location. 

This Powershell script will accomplish backup a domain user's Windows profile, backup browsing bookmarks and/or profiles, in addition to logging their mapped printers and network shares, to a designated network location. I also used Trevor Sullivan's advanced 'Robocopy w/Progress Bar' function so that when running during a Powershell session, you can view a progress bar (https://stackoverflow.com/questions/13883404/custom-robocopy-progress-bar-in-powershell).

I have written a second script (powerShellMigrateUserProfile), that will migrate this data, and re-map printers and shares back to the user's recently deployed PC refresh.

I will update the Readme with the specific line numbers, but for this script to work on your local network, you will need to fill in several lines with filepath strings, to match your network filepath folder names. 
