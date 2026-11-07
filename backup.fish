#SECTION - Global variables and checks
set RCON_HOST $env[RCON_HOST]
set RCON_PORT $env[RCON_PORT]
set RCON_BACKUP_MESSAGE $env[RCON_BACKUP_MESSAGE]
set RCON_PASSWORD (string trim < cat /run/secrets/rcon_password)

# TODO - verify is alladis is even working.
set DATA_FOLDER "/app/data-folder"
set BACKUPS_FOLDER "/app/backups-folder"
set TEMP_BACKUP_FOLDER "/app/temp-backup-folder" # Gets created

if test -z "$RCON_HOST" -o -z "$RCON_PORT"
    echo "welp, nothing's set. set RCON_HOST and RCON_PORT first." >&2
    exit 1
end

if not test -d "$DATA_FOLDER"
    echo "DATA_FOLDER doesn't exist"
    exit 1
end

if not test -d "$BACKUPS_FOLDER"
    echo "BACKUPS_FOLDER doesn't exist!"
    exit 1
end
#!SECTION

# Kick all players
rcon-cli --host "$RCON_HOST" --port "$RCON_PORT" --password "$RCON_PASSWORD" -- "kick @a $RCON_BACKUP_MESSAGE"

#TODO - Write code to somehow execute `docker compose down`

# Copy data folder to a temp folder so the server can immediately start
mkdir $TEMP_BACKUP_FOLDER
or begin
    echo "Coudln't create temporary backup folder." >&2
    exit 1
end

set DATE_NOW (date +%s)
cp -a $DATA_FOLDER/. $TEMP_BACKUP_FOLDER/
or begin
    echo "Couldn't copy data folder. Backup failed" >&2
    exit 1
end

#REVIEW - Should the server immediately start or should it wait for 7z to finish...
#TODO - Write code to somehow execute `docker compose up -d`

#SECTION Create archive and move to backup folder
#REVIEW - I think the user should be able to set their own compression level, no...?
cd $TEMP_BACKUP_FOLDER
7z a -t7z -m0=lzma2 -mx=9 -bsp1 "$DATE_NOW.7z" .
or begin
    echo "Failed to create archive. Backup failed!"
    exit 1
end

mkdir "$BACKUPS_FOLDER/$DATE_NOW"
or begin
    echo "Failed to make backup folder"
    exit 1
end
mv "$DATE_NOW.7z" "$BACKUPS_FOLDER/$DATE_NOW"
#!SECTION

#SECTION Create parity files in archive's backup folder
cd "$BACKUPS_FOLDER/$DATE_NOW"
par2 c -r10 "$DATE_NOW.7z"
or echo "WARNING: Archive has no parity data. Failed to generate"
#!SECTION

echo "Finished creating backup $DATE_NOW"