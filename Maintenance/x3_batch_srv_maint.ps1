#====================================================================================
#
# SCRIPT:  X3_BATCH_SRV_MAINT.PS1
# AUTOR:   JORDI BONILLO
# FECHA:   19-02-2024
#
# POWERSHELL SCRIPT 
# CLEANING TRACE FILES OF SAGE X3 BATCH SERVER FROM OUTSIDE THE X3 APPLICATION
# MADE FOR A STANDALONE X3 INSTALLATION IN A WINDOWS ENVIRONMENT
#
#==================================================================================== 
#
# ALTOUGH SAGE X3 INCLUDES AN ARCHIVING/PURGING SYSTEM FOR TRACE (.TRA) FILES BY FOLDER,
# OTRHER FILES LIKE
#
#   /x3/SRV/TRA/serveur.tra
#   /x3/SRV/TRA/RQTxxxxxx.tra
#   ...
#
# SHOULD BE CLEANED MANUALLY
#
# IN ORDER TO AUTOMATIZE THE MAINTENANCE AND AVOID BATCH ERRORS AND SUDDENLY STOPS,
# EXECUTE THIS SCRIPT ON THE FIRST DAY OF THE MONTH AT NON-WORKING HOURS.
#
#
# WHAT DOES IT DO?
# 1) CHECK THE BATCH SERVER STATUS VÍA REST WEB-SERVICE CALL
# 2) STOPS THE SERVER IF NECCESARY. ONCE IT IS STOPPED, VERIFY/CREATE BACKUP FOLDERS
# 3) FOR EACH WORK FOLDER, COPY/MOVE THE OLD .TRA FILES AND CLEAN ACCENTRY.TRA
# 4) FOR THE REFERENCE FOLDER (X3), COPY/MOVE THE OLD .TRA FILES AND CLEAN SERVEUR.TRA
# 5) STARTS THE BATCH SERVER, EVEN IF IT WAS STOPPED
#
#====================================================================================

#====================================================================================
#
#        HOW TO CHECK IF THE BATCH SERVER IS RUNNING FROM OUTSIDE SAGE X3?
#
#====================================================================================
# Using API1 service call for versions 2017Rx / 2018R1 and future V12 (POST method)
#  http://SERVER/NAME/api1/syracuse/collaboration/syracuse/batchServers(code eq "BATCH-SERVER-CODE")/$service/stop
#  http://SERVER/NAME/api1/syracuse/collaboration/syracuse/batchServers(code eq "BATCH-SERVER-CODE")/$service/stopAll
#  http://SERVER/NAME/api1/syracuse/collaboration/syracuse/batchServers(code eq "BATCH-SERVER-CODE")/$service/start
#  http://SERVER/NAME/api1/syracuse/collaboration/syracuse/batchServers(code eq "BATCH-SERVER-CODE")/$service/status
#
#
# Using batch server dispatcher for 2017Rx / 2018R1, V11 and future V12 (GET method)
#  http://SERVERNAME/batch/stop/?code=BATCH-SERVER-CODE
#  http://SERVERNAME/batch/stopAll/?code=BATCH-SERVER-CODE
#  http://SERVERNAME/batch/start/?code=BATCH-SERVER-CODE
#  http://SERVERNAME/batch/status/?code=BATCH-SERVER-CODE - status command only for 2017Rx / 2018R1 and future V12
#====================================================================================


#====================================================================================
#
#                                      VARIABLES 
#
#====================================================================================
# X3 WEB SERVICE VARIABLES
# REPLACE xXxXxXxX WITH THE LOGIN OF AN X3 USER WITH PERMISSIONS TO STOP BATCH SERVER
$x3LoginBase64 = 'Basic xXxXxXxX'

$batchServerName = "SMIRAX3"
$server = 'localhost'                                                                  
$port = '8124'
$protocol = 'http'                                                     #Plain HTTP use for simplicity. Use it only in localhost.

#'http://localhost:8124/api1/syracuse/collaboration/syracuse/batchServers...'
$urlStatus = $protocol + '://' + $server + ':' + $port + '/api1/syracuse/collaboration/syracuse/batchServers'
$urlStart  = $protocol + '://' + $server + ':' + $port + '/api1/syracuse/collaboration/syracuse/batchServers(code eq "'+$batchServerName+'")/$service/start'
$urlStop   = $protocol + '://' + $server + ':' + $port + '/api1/syracuse/collaboration/syracuse/batchServers(code eq "'+$batchServerName+'")/$service/stop'

# SERVER VARIABLES
$drive                 = "E:\"
$driveBackup           = "F:\"
$backupBaseFolder      = "BackupX3BatchSrv\"                                            # End with \

# X3 INSTALL VARIABLES
# REPLACE xXxXxXxX WITH THE WORK FOLDER NAMES YOU WANT THE SCRIPT TO CLEAN. AVOID X3 BASE FOLDER.
$x3DossierArray         = @("xXxXxXxX", "xXxXxXxX", "xXxXxXxX")
$x3DossierDir           = "E:\xXxXxXxX\xXxXxXxX\folders\"                               # End with \
$x3DossierTRAFolder     = "\TRA\"                                                       # Start and end with \
$x3BaseDossierTRAFolder = "x3\SRV\TRA\"                                                 # End with \
$accentryLogFileName    = "ACCENTRY.tra"
$batchLogFileName       = "serveur.tra"

#====================================================================================


Write-Output "---------------------------------------------------"
Write-Output "--- SCRIPT MANTENIMIENTO SERVIDOR BATCH SAGE X3 ---"
Write-Output "---------------------------------------------------"


#====================================================================================
#
# 1) CHECK BATCH SERVER STATUS VÍA HTTP GET PETITION WITH SELECTED USER
#
#====================================================================================
# Create web request with "Authorization" header
$HEADERS = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$HEADERS.Add("Authorization", $x3LoginBase64)

# Get the WebServer response and parse the status
$RESPONSE = Invoke-RestMethod $urlStatus -Method 'GET' -Headers $HEADERS
$STATUS = $RESPONSE.'$resources'.status
Write-Output "El servidor batch está en estado: $STATUS"

# If needed, stop the batch server:
if ($STATUS -eq "running") {
    $RESPONSE = Invoke-RestMethod $urlStop   -Method 'POST' -Headers $HEADERS
    $RESPONSE = Invoke-RestMethod $urlStatus -Method 'GET'  -Headers $HEADERS
    
    # Stop the script execution to give the Server enough time to finish properly
    # Should improve it by looping an status check 
    Write-Output "Paramos el batch. Pasuamos ejecución del script hasta que se detenga..."
    Start-Sleep 15
} 
#====================================================================================


#====================================================================================
#
# 2) CHECK IF THE SERVER IS REALLY STOPPED. IF SO:
#        CHECK IF THE BACKUP FOLDER STRUCTURE IS OK
#        COPY/MOVE THE FILES TO THE BACKUP FOLDERS
#        CLEAN THE LONG LOG FILES: ACCENTRY.tra, SERVEUR.tra
#       
#====================================================================================
$RESPONSE = Invoke-RestMethod $urlStatus -Method 'GET' -Headers $HEADERS
$STATUS = $RESPONSE.'$resources'.status

if ($STATUS -eq "stopped") {
    Write-Output "Batch detenido"
    Write-Output "Creando directorios y lanzando copia de ficheros"

    $fechaCarpeta = (Get-Date).AddMonths(-1).ToString("yyyyMM")
    $carpetaBackup = $driveBackup+$backupBaseFolder+$fechaCarpeta+"\"


    # FOR THE WORKING X3 DOSSIERS
    foreach ($dossier in $x3DossierArray) {
        Write-Output "Trabajando en dossier $dossier"

        # Source and destination folder
        $carpetaOrigen  = $x3DossierDir  + $dossier + $x3DossierTRAFolder
        $carpetaDestino = $carpetaBackup + $dossier

        # Test if destination folder exists. If not, create it.
        if (-not (Test-Path -Path $carpetaDestino -PathType Container)) {        
            New-Item -Path $carpetaDestino -ItemType Directory
        }

        # Copio los ficheros que me interesan
        #Get-ChildItem -Path $carpetaOrigen | Where-Object {($_.LastWriteTime -gt (Get-Date).AddDays(-30))} | Copy-Item -Destination $carpetaDestino
        Get-ChildItem -Path $carpetaOrigen | Where-Object {($_.LastWriteTime -gt (Get-Date).AddMonths(-1))} | Move-Item -Destination $carpetaDestino
        
        #Limpio el fichero origen
        Clear-Content $carpetaOrigen+$accentryLogFileName
    }


    # FOR THE X3 REFERENCE DOSSIER
    # DOES THE SAME IN A DIFFERENT SOURCE FOLDER
    Write-Output "Trabajando en dossier x3"
    $carpetaOrigen  = $x3DossierDir  + $x3BaseDossierTRAFolder
    $carpetaDestino = $carpetaBackup + $x3BaseDossierTRAFolder

    if (-not (Test-Path -Path $carpetaDestino -PathType Container)) {        
        New-Item -Path $carpetaDestino -ItemType Directory
    }

    Get-ChildItem -Path $carpetaOrigen | Where-Object {($_.LastWriteTime -gt (Get-Date).AddMonths(-1))} | Move-Item -Destination $carpetaDestino

    Clear-Content $carpetaOrigen+$batchLogFileName
}
#====================================================================================


#====================================================================================
#
# 3) START THE BATCH SERVER
#
#====================================================================================
if ($STATUS -eq "stopped") {
    $RESPONSE = Invoke-RestMethod $urlStart  -Method 'POST' -Headers $HEADERS
    $RESPONSE = Invoke-RestMethod $urlStatus -Method 'GET'  -Headers $HEADERS
    $STATUS = $RESPONSE.'$resources'.status
    Write-Output "El servidor batch se queda en estado $STATUS"
    Start-Sleep 5
}

Exit
