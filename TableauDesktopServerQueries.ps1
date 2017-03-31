<# 
.SYNOPSIS 
A script that exports SQL select queries from Tableau Desktop and/or Server log files.
.DESCRIPTION 
This project came to exist when someone asked me to find out what queries users were creating in Tableau so they can review them and possibly reuse them in other systems. It's my first try at getting 
this accomplished, and my improve over time or be wiped if I find out it isn't the best way to get it done :P
.EXAMPLE 
Edit the script's list of computers and then run it using an account that has access to those systems.

###
Copyright (c) 2017 Greg Besso

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#>


# static array for now. can be fed list of all computers that have Tableau Desktop if needed...
$tqSystems = @('gregtabdesk-lp','gregtab01-srv')
$tqDestination = '\\soemServer\someShare\TableauQueries'

# an array to keep track of what files to scan for queries...    
$theseFiles = @()

# loop through each computer...
$tqSystems | ForEach-Object {
    $thisComputer = $_
    Write-Host "computer is $thisComputer"

    # see if the computer is a server. if it is, there is a path for that...
    $thisServerFile = "\\$thisComputer\c$\ProgramData\Tableau\Tableau Server\data\tabsvc\logs\vizqlserver\tabprotosrv.txt"
    If (Test-Path "$thisServerFile") { $theseFiles += "$thisServerFile" }


    $getUsers = $getFiles = Get-ChildItem -Path "\\$thisComputer\c$\Users"
    

    # loop through each user on the computer...
    $getUsers | ForEach-Object {
        $thisUser = $_        
        $thisRepository = "\\$thisComputer\c$\Users\$thisUser\Documents\My Tableau Repository"
        If (Test-Path "$thisRepository") {

            If (Test-Path "$thisRepository\Logs\log.txt") { $theseFiles += "$thisRepository\Logs\log.txt" }
            If (Test-Path "$thisRepository\Logs\tabprotosrv.txt") { $theseFiles += "$thisRepository\Logs\tabprotosrv.txt" }
        }
        # END this user
    }
    # END this computer
}



# targets acquired, now let's do this...
$theseFiles | ForEach-Object {
    # START file processing...
    $thisFile = $_

    # get username from file path, if there is one...
    If ($thisFile -Like '*\Users\*') {
        $thisUserSam = $thisFile.Split("\")
        $thisComputer = $thisUserSam[2]
        $thisUserSam = $thisUserSam[5]
    } Else { 
        $thisComputer = $thisFile.Split("\")
        $thisComputer = $thisComputer[2]
        $thisUserSam = 'NONE'
    }


    $thisFileName = $thisFile.Split("\")
    $thisFileName = $thisFileName[-1]
    Write-Host "file is $thisFileName"
    $thisFileNameNoExt = $thisFileName.Split(".")
    $thisFileNameNoExt = $thisFileNameNoExt[0]
    $getJson = Get-Content -Path "$thisFile" # | ConvertFrom-Json
    $getJSON.GetType()

    # want to store the time query was last extracted. not sure which format i like better yet...
    $rightNow = Get-Date
    $rightNowFlat = (Get-Date -Format yyyyMMddhhmm)

    # loop through every record in the file, only extract from lines with 'begin-query'...
    $getQueries = @()
    $getJSON | ForEach-Object {
        $test = $_ | ConvertFrom-Json
        If ($test.k -eq 'begin-query') {
            $v = $test.v
            # only care about select statements for now...
            If ($v.query -like 'select*') {
                # picking what values i want to store. this will change probably...
                $vQuery = $v.query
                $vQueryCategory = $v.'query-category'
                $vQueryHash = $v.'query-hash'
                $vProtocolId = $v.'protocol-id'
                $ts = $test.ts
                $thisUser = $test.user
                $tsFlat = $ts.Replace("-","").Replace(":","").Replace(".","")
                # some files have more columns than others...
                If ($thisFile -Like '*tabprotosrv*') {
                    $vProductVersion = $v.'product-version'
                } Else { $vProductVersion = '' }

                # making a new object with the chosen columns, to be exported to xml...
                $object1 = New-Object PSObject -Property @{                                
                    vQueryCategory=$vQueryCategory;
                    vQueryHash=$vQueryHash;
                    vProtocolId=$vProtocolId;
                    vProductVersion=$vProductVersion;
                    qTs=$ts;
                    qDesktop=$thisComputer;
                    qTsFlat=$tsFlat;
                    qUser=$thisUser;
                    qSamAccountName=$thisUserSam;
                    qFile=$thisFileName;
                    qWhenGathered=$rightNow;
                    qWhenGathered2=$rightNowFlat;
                    spListAction='add';
                    spListName='TableauServerQueries';
                    vQuery=$vQuery;
                }
                # exporting the query to be processed by another separate process...
                $object1 | Export-Clixml "$tqDestination\$thisComputer-$thisUserSam-$thisFileNameNoExt-$vQueryHash.xml" -Force
            }
        }

    }
    # END file processing
}
# END this repository
