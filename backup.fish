#SECTION - Global variables and checks
function restart_on_exit --on-event fish_exit
    docker -H host.docker.internal:2375 compose -p "$DOCKER_PROJECT_NAME" start
end

set RCON_PASSWORD (cat /run/secrets/rcon_password | string trim)

# Folders
set DATA_FOLDER "/app/data-folder"
set BACKUPS_FOLDER "/app/backups-folder"
set TEMP_BACKUP_FOLDER "/var/tmp/mc-backup" # Gets created in Dockerfile

for var in RCON_HOST RCON_PORT DOCKER_PROJECT_NAME
    if test -z "$$var"
        echo "$var not set" >&2
        exit 1
    end
end

# Test if the data folder and the backup folder actually exists
if not test -d "$DATA_FOLDER"
    echo "DATA_FOLDER doesn't exist" >&2
    exit 1
end

if not test -d "$BACKUPS_FOLDER"
    echo "BACKUPS_FOLDER doesn't exist!" >&2
    exit 1
end
#!SECTION

#SECTION Step 1 - Kick all players to turn off the server and yeah
echo -e "Step 1: Kicking Players and Stopping the Server"
rcon-cli --host "$RCON_HOST" --port "$RCON_PORT" --password "$RCON_PASSWORD" -- "kick @a $RCON_BACKUP_MESSAGE"
if test $status -ne 0
    echo -e "\tWARNING: Couldn't kick players"
else
    echo -e "\tKicked Players with Message \"$RCON_BACKUP_MESSAGE\""
end

docker -H host.docker.internal:2375 compose -p "$DOCKER_PROJECT_NAME" stop $DOCKER_SERVICES #REVIEW this takes EVERYTHING down. and apparently i should add -t 60 or sum
if test $status -ne 0 #REVIEW - It doesn't execute this when the project name doesn't exist
    echo -e "\tFATAL: Couldn't stop docker container(s)." >&2
    exit 1
else
    echo -e "\tStopped Docker Container(s)"
end
#!SECTION

#SECTION Step 2 - Copy data folder toa temp folder
echo "Step 2: Copying Data Folder to Temp Folder"

set DATE_NOW (date "+%Y-%m-%d-%H-%M")
cp -a $DATA_FOLDER/. $TEMP_BACKUP_FOLDER/
if test $status -ne 0
    echo -e "\tFATAL: Couldn't copy data folder!" >&2
    exit 1
else
    echo -e "\tCopied Data Folder to Temp Folder"
end

if test $status -ne 0
    echo -e "\tWARNING: Couldn't get the server back up." >&2
else
    echo -e "\tServer started again"
end
#!SECTION

#SECTION Step 3 - Create archive and move to backup folder
echo "Step 3: Creating 7zip Archive"

cd $TEMP_BACKUP_FOLDER
#REVIEW - I think the user should be able to set their own compression level, no...?
7z a -t7z -mx=9 -m0=lzma2 -mmemuse=7g "$DATE_NOW.7z" . # Use 7gb of memory, hot damn.
# TODO - Add an option in compose to select whether to use 7z or tarball
if test $status -ne 0
    echo -e "\tFATAL: Failed to create archive!" >&2
    exit 1
else
    echo -e "\tCreated 7zip archive"
    docker -H host.docker.internal:2375 compose -p "$DOCKER_PROJECT_NAME" start $DOCKER_SERVICES  #REVIEW this takes EVERYTHING down.
end

mkdir "$BACKUPS_FOLDER/$DATE_NOW"
if test $status -ne 0
    echo -e "\tFATAL: Failed to make backup folder" >&2
    exit 1
else
    echo -e "\tCreated backup directory inside backups folder"
end

mv "$DATE_NOW.7z" "$BACKUPS_FOLDER/$DATE_NOW"
if test $status -ne 0
    echo -e "\tFATAL: Failed to move archive to backup folder!" >&2
    exit 1
else
    echo -e "\tMoved 7zip archive to backups folder"
end
#!SECTION

#SECTION Step 4 Create parity files in archive's backup folder
echo "Step 4: Parity file creation"

cd "$BACKUPS_FOLDER/$DATE_NOW"
par2 c -r10 "$DATE_NOW.7z"
if test $status -ne 0
    echo -e "\tWARNING: Archive has no parity data. Failed to generate!" >&2
else
    echo -e "\tParity files created."
end
#!SECTION

echo "Finished creating backup $DATE_NOW"