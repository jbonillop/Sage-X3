## VERIFICAR SI TOMA RESTO CARPETAS QUE NO SON SMIRA
## VERIFICAR SI MUEVE LOS FICHEROS O SOLO LOS COPIA
## Quito el mas de la línea Clear-Content
## Ajusto programador de tareas para ejecutarse "Con los privilegios más altos"

#====================================================================================
#
# CÓDIGO:  ZSCSBPT.SRC
# AUTOR:   JORDI BONILLO
# FECHA:   19-02-2024
#
# LIMPIEZA DE FICHEROS DE TRAZA DE SERVIDOR BATCH X3 DESDE FUERA DE LA APLICACIÓN
# 
# PESE A QUE X3 INCLUYE UN SISTEMA DE ARCHIVADO/PURGADO PARA LOS FICHEROS DE TRAZA
# QUE GENERAN LAS TAREAS POR CADA DOSSIER, LOS DATOS RELATIVOS A LOS FICHEROS
#
#   /X3/SRV/TRA/serveur.tra
#   /X3/SRV/TRA/RQTxxxxxx.tra
#   /DOSSIER/TRA
#
# HAY QUE SEGUIR LIMPIÁNDOLOS MANUALMENTE.
# PARA EVITAR ESTO:
#
# 1) COMPROBAMOS EL ESTADO DEL SERVIDOR BATCH VÍA REST WEB SERVICES
# 2) UNA VEZ SABEMOS QUE ESTÁ PARADO, REVISAMOS LA ESTRUCTURA DE CARPETAS DE BACKUP
# 3) LIMPIAMOS DE LAS CARPETAS ARCHIVOS DE TRAZA MUY VIEJOS
# 4) MOVEMOS LOS FICHEROS DESDE LAS CARPETAS X3 QUE NOS INTERESEN A LA ZONA BACKUP
#
#
# El Script está pensado para ejecutrase el día 1 de cada mes. 
# Copia todas las trazas del mes pasado a una carpeta nueva con el mes y el año
#
#====================================================================================

#====================================================================================
#Using API1 service call for versions 2017Rx / 2018R1 and future V12 (POST method)
#http://SERVER/NAME/api1/syracuse/collaboration/syracuse/batchServers(code eq "BATCH-SERVER-CODE")/$service/stop
#http://SERVER/NAME/api1/syracuse/collaboration/syracuse/batchServers(code eq "BATCH-SERVER-CODE")/$service/stopAll
#http://SERVER/NAME/api1/syracuse/collaboration/syracuse/batchServers(code eq "BATCH-SERVER-CODE")/$service/start
#http://SERVER/NAME/api1/syracuse/collaboration/syracuse/batchServers(code eq "BATCH-SERVER-CODE")/$service/status


#Using batch server dispatcher for 2017Rx / 2018R1, V11 and future V12 (GET method)
#http://SERVERNAME/batch/stop/?code=BATCH-SERVER-CODE
#http://SERVERNAME/batch/stopAll/?code=BATCH-SERVER-CODE
#http://SERVERNAME/batch/start/?code=BATCH-SERVER-CODE
#http://SERVERNAME/batch/status/?code=BATCH-SERVER-CODE - status command only for 2017Rx / 2018R1 and future V12
#====================================================================================


#====================================================================================
#
#                                             VARIABLES 
#
#====================================================================================
# X3 WEB SERVICE
$x3LoginBase64 = 'WlgzU01BUFBXRUJTVkNTOjFMVmRrQnRob09QbkFndA'

$batchservername = "SMIRAX3"
$server = 'localhost'                                                                  #Uso http por ejecución en local
$port = '8124'
$protocol = 'http'

#'http://localhost:8124/api1/syracuse/collaboration/syracuse/batchServers...'
$urlStatus = $protocol + '://' + $server + ':' + $port + '/api1/syracuse/collaboration/syracuse/batchServers'
$urlStart  = $protocol + '://' + $server + ':' + $port + '/api1/syracuse/collaboration/syracuse/batchServers(code eq "'+$batchservername+'")/$service/start'
$urlStop   = $protocol + '://' + $server + ':' + $port + '/api1/syracuse/collaboration/syracuse/batchServers(code eq "'+$batchservername+'")/$service/stop'

# SERVIDOR
$unidad                 = "E:\"
$unidadBackup           = "F:\"
$carpetaBackupBase      = "BackupX3BatchSrv\"                                           # Ha de terminar con \

# X3 INSTALACIÓN
$x3DossierArray         = @("SMIRA", "SMIRAPRE", "ALMSOL", "ALMSOLPRE")

$x3DossierDir           = "E:\SAGE\SMIRAX3\folders\"                                    # Ha de terminar con \
$x3DossierTRAFolder     = "\TRA\"                                                       # Ha de empezar y terminar con \
$x3BaseDossierTRAFolder = "x3\SRV\TRA\"                                                 # Ha de terminar con \
$accentryLogFileName    = "ACCENTRY.tra"
$batchLogFileName       = "serveur.tra"

#====================================================================================

Write-Output "---------------------------------------------------"
Write-Output "--- SCRIPT MANTENIMIENTO SERVIDOR BATCH SAGE X3 ---"
Write-Output "---------------------------------------------------"


#====================================================================================
#
# 1) COMPROBAMOS EL ESTADO DEL SERVIDOR BATCH VÍA REST WEB SERVICES
#
#====================================================================================

# Monto la petición web con usuario ADMINSM
$HEADERS = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$HEADERS.Add("Authorization", "Basic $x3LoginBase64")

# Obtengo estado del servidor Batch vía llamada WS con método GET
$RESPONSE = Invoke-RestMethod $urlStatus -Method 'GET' -Headers $HEADERS
$STATUS = $RESPONSE.'$resources'.status
Write-Output "El servidor batch está en estado: $STATUS"

# Según el status, actúo...
if ($STATUS -eq "running") {
    $RESPONSE = Invoke-RestMethod $urlStop -Method 'POST' -Headers $HEADERS
    $RESPONSE = Invoke-RestMethod $urlStatus -Method 'GET' -Headers $HEADERS
    
    # Espero a que esté parado del todo
    Write-Output "Paramos el batch. Pasuamos ejecución del script hasta que se detenga..."
    Start-Sleep 10
#
} 
#====================================================================================



#====================================================================================
#
# 2) UNA VEZ SABEMOS QUE ESTÁ PARADO, 
#        REVISAMOS LA ESTRUCTURA DE CARPETAS DE BACKUP,
#        HACEMOS LA COPIA DE LOS FICHEROS,
#        DEJAMOS LOS FICHEROS DE TRAZA LIMPIOS.
#       
#====================================================================================

$RESPONSE = Invoke-RestMethod $urlStatus -Method 'GET' -Headers $HEADERS
$STATUS = $RESPONSE.'$resources'.status
if ($STATUS -eq "stopped") {
    Write-Output "Batch detenido"
    Write-Output "Creando directorios y lanzando copia de ficheros"

    $fechaCarpeta = (Get-Date).AddMonths(-1).ToString("yyyyMM")
    $carpetaBackup = $unidadBackup+$carpetaBackupBase+$fechaCarpeta+"\"
    #Write-Output $carpetaBackup


    # ACTÚO PARA LOS DOSSIERES DE TRABAJO
    foreach ($dossier in $x3DossierArray) {
        Write-Output "Trabajando en dossier $dossier"
        # Carpeta origen
        $carpetaOrigen = $x3DossierDir+$dossier+$x3DossierTRAFolder

        # Carpeta destino
        $carpetaDestino = $carpetaBackup+$dossier

        # Compruebo si la carpeta destino existe. Si no, la creo.
        if (-not (Test-Path -Path $carpetaDestino -PathType Container)) {        
            New-Item -Path $carpetaDestino -ItemType Directory
        }

        # Copio los ficheros que me interesan
        Get-ChildItem -Path $carpetaOrigen | Where-Object {($_.LastWriteTime -gt (Get-Date).AddDays(-30))} | Move-Item -Destination $carpetaDestino

        #Limpio el fichero origen
        Clear-Content $carpetaOrigen$accentryLogFileName
    }


    # ACTÚO PARA EL DOSSIER X3
    # Hago lo mismo pero para el dossier de referencia (x3) que tiene una carpeta diferente al resto
    Write-Output "Trabajando en dossier x3"
    $carpetaOrigen = $x3DossierDir+$x3BaseDossierTRAFolder
    $carpetaDestino = $carpetaBackup+$x3BaseDossierTRAFolder

    if (-not (Test-Path -Path $carpetaDestino -PathType Container)) {        
        New-Item -Path $carpetaDestino -ItemType Directory
    }

    # Copio ficheros
    Get-ChildItem -Path $carpetaOrigen | Where-Object {($_.LastWriteTime -gt (Get-Date).AddDays(-30))} | Move-Item -Destination $carpetaDestino

    # Limpio traza
    Clear-Content $carpetaOrigen$batchLogFileName
}
#
#====================================================================================




#====================================================================================
#
# 3) VUELVO A PONER EN MARCHA EL SERVIDOR BATCH
#
#====================================================================================
if ($STATUS -eq "stopped") {
    $RESPONSE = Invoke-RestMethod $urlStart -Method 'POST' -Headers $HEADERS
    $RESPONSE = Invoke-RestMethod $urlStatus -Method 'GET' -Headers $HEADERS
    $STATUS = $RESPONSE.'$resources'.status
    Write-Output "El servidor batch se queda en estado $STATUS"
    Start-Sleep 5
}

Exit
