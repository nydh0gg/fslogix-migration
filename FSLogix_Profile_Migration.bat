@echo off
REM ::  //////////////////////////////////////////////////////////////////
REM ::  BATCH script for migrating windows profiles to FSLogix profiles
REM ::  Written by: u/nydh0gg
REM ::  Updated: 2023-12-14
REM ::  //////////////////////////////////////////////////////////////////

REM ::  //////////////////////////////////////////////////////////////////
REM ::  User domain if applicable, if not applicable then make it blank
set     domain=DOMAIN\
REM ::  Temporary directory location
set     tempdir=C:\temp
REM ::  Destination of converted profile
set     profiledestination=\\file-share\profiles
REM ::  Location of directory containing FSLogix installation files (specifically FSLogixAppsSetup.exe)
set     fslogixinstall=\\file-share\FSLogixInstall
REM ::  //////////////////////////////////////////////////////////////////

echo //////////////////////////////////////////////////////////////////
echo Performing FSLogix Profile Migration Prerequistes and checks...
echo //////////////////////////////////////////////////////////////////

REM ::  Install FSLogix if it is not already installed
if not exist "C:\Program Files\FSLogix" ( call :install )
REM ::  Create temporary directory if it doesn't already exist
if not exist "%tempdir%" ( mkdir %tempdir% )

REM ::  Add registry key to define robocopy log file path for error checking
echo Adding Robocopy Log Path registry key...
reg query HKEY_LOCAL_MACHINE\SOFTWARE\FSLogix\Logging /v RobocopyLogPath > nul
if %errorlevel%==1 (
    reg add HKEY_LOCAL_MACHINE\SOFTWARE\FSLogix\Logging /v RobocopyLogPath /t REG_SZ /d "%tempdir%\RobocopyLog.txt"
)

REM ::  Delete Microsft Cache files (if exists) that FRX profile conversion frequently gets stuck on
echo Deleting Microsoft CryptnetURLCache...
rmdir /s /q "%localappdata%\Packages\Microsoft.MicrosoftOfficeHub_8wekyb3d8bbwe\LocalCache"

echo Prerequisites and checks completed.

REM ::  Perform profile migration
echo //////////////////////////////////////////////////////////////////
echo Converting local user profile to FSLogix profile container...
cd C:\Program Files\FSLogix\Apps
frx.exe copy-profile -filename %tempdir%\Profile_%computername%.vhdx -username %domain%%computername% -dynamic 1 -vhdx-sector-size 4096 -verbose

echo FSLogix profile conversion process ended...

REM ::  Check for common errors and apply associated fixes
echo //////////////////////////////////////////////////////////////////
echo Error Checking Sequence Beginning...
echo //////////////////////////////////////////////////////////////////

if %errorlevel%==-2147023582 ( call :522 )
if %errorlevel%==-2147024894 ( call :002 )
if %errorlevel%==-2147024814 ( call :052 )
if %errorlevel%==-2147024809 ( call :SID )

REM ::  If an error occurs that isn't specified, end the script and provide error code
if not %errorlevel% == 0 (
    echo Unexpected FRX error "%errorlevel%" occured, script now ending prematurely
    pause
    exit
)

echo FSLogix profile conversion error checking process completed, continuing... 

REM :: Move newly converted file to SHCS Profile file server
echo //////////////////////////////////////////////////////////////////
echo Migrate FSLogix Profile to File Server
echo //////////////////////////////////////////////////////////////////

REM ::  Map network location then move converted profile to it
pushd "%profiledestination%"
md "%profiledestination\%computername%"
esentutl /y "%tempdir%\Profile_%computername%.vhdx" /d "%profiledestination%\%computername%\Profile_%computername%.vhdx" /o
echo Profile file moved to %profiledestination%

REM :: Grant user owner and FA permissions to user's new directory and files within
echo Adjusting File and Folder Permissions...
icacls "%profiledestination%\%computername%" /setowner "%domain%%computername%" /t
icacls "%profilesdestination%\%computername%" /grant "%domain%%computername%":(OI)(CI)f /t
popd

echo //////////////////////////////////////////////////////////////////
echo FSLogix Profile Migration Complete
echo //////////////////////////////////////////////////////////////////
pause
exit

REM ::  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

REM ::  //////////////////////////////////////////////////////////////////
REM ::                         Install FSLogix
REM ::
:install
echo FSLogix not installed,installing FSLogix now...
pushd %fslogixinstall%
FSLogixAppsSetup.exe /install /passive /norestart
popd
goto :eof

REM ::
REM ::
REM ::  //////////////////////////////////////////////////////////////////
REM ::                         Error Resolutions
REM ::
REM ::  Error 0x000000522 - Required priviledge not met, user needs to re-run .bat file in admin mode
:522
    echo Script is missing permissions, please try re-running script as administrator.
    pause
    exit

REM ::  Error 0x000000002 - Re-run profile migration, this error will resolve itself on 2nd run
:002
    echo Resolving Error 02 by re-attempting profile migration...
    frx.exe copy-profile -filename %tempdir%\Profile_%computername%.vhdx -username %domain%%computername% -dynamic 1 -vhdx-sector-size 4096 -verbose
    goto :eof

REM ::  Error 0x000000052 - Robocopy Error, erroneous file will need to be manually deleted
:052
    echo Robocopy error with copying profile, please check robocopy log file at %tempdir%
    pause
    exit

REM ::  Unable to resolve username or SID not specified - FRX Profile migration error, caused by incorrect DOMAIN username
:SID
    echo Username "%computername%" is not valid, please copy this script to the users desktop and do a text replcement for the computername variable with the users apropriate username
    pause
    exit

REM ::
REM ::
REM ::  //////////////////////////////////////////////////////////////////