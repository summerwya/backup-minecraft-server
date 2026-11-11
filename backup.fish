#SECTION - Global variables and checks
# REVIEW - Rename to "start_docker_services" ?
function restart_on_exit --on-event fish_exit
    if not test -z "$DOCKER_PROJECT_NAME"
        docker -H "$DOCKER_DAEMON_ADDRESS" compose -p "$DOCKER_PROJECT_NAME" start -- $DOCKER_SERVICES
    end
end

#REVIEW - Sometimes i wish I never wrote all of this in fish shell and just wrote the logic in typescript-bun. Or Java. Or even better to learn Rust.
function __backup_period_key --argument-names stamp limit
    set -l y (string sub -s 1 -l 4 -- $stamp)
    set -l m (string sub -s 6 -l 2 -- $stamp)
    set -l d (string sub -s 9 -l 2 -- $stamp)

    switch $limit
        case day
            printf '%s-%s-%s\n' $y $m $d
        case month
            printf '%s-%s\n' $y $m
        case week
            set -l iso (date -d "$y-$m-$d" +"%G-%V" 2>/dev/null)
            if test -n "$iso"
                printf '%s\n' $iso
            else
                set -l doy (date -d "$y-$m-$d" +"%j" 2>/dev/null)
                printf '%s-%02d\n' $y (math "floor(($doy - 1) / 7)")
            end
    end
end

function prune_old_backups --argument-names limit
    if test -z "$limit"
        return
    end

    set -l backups
    for entry in "$BACKUPS_FOLDER"/*
        test -d "$entry"; or continue
        set -l name (basename -- "$entry")
        string match -q -r '^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9]$' -- $name; or continue #dioskopo
        set -a backups $name
    end

    if not set -q backups[1]
        return
    end

    set -l sorted (printf '%s\n' $backups | sort)
    set -l current_key (__backup_period_key (date "+%Y-%m-%d-%H-%M") $limit)
    set -l current_num (string replace -a -- "-" "" $current_key)
    set -l seen

    for name in $sorted[-1..1]
        set -l key     (__backup_period_key $name $limit)
        set -l key_num (string replace -a -- "-" "" $key)

        if test $key_num -lt $current_num
            if contains -- $key $seen
                echo "Pruning old backup: $name"
                rm -rf -- "$BACKUPS_FOLDER/$name"
            else
                set -a seen $key
            end
        end
    end
end

# Folders
set DATA_FOLDER "/app/data-folder"
set BACKUPS_FOLDER "/app/backups-folder"

# Test if the data folder and the backup folder actually exists
if not test -d "$DATA_FOLDER"
    echo "\"$DATA_FOLDER\" (data folder) doesn't exist" >&2
    exit 1
end

if not test -d "$BACKUPS_FOLDER"
    echo "\"$BACKUPS_FOLDER\" (backups folder) doesn't exist!" >&2
    exit 1
else if not test -w "$BACKUPS_FOLDER"
    echo "\"$BACKUPS_FOLDER\" (backups folder) is not writable!" >&2
    exit 1
end

#SECTION - Check Docker and RCON configuration
if test -z "$DOCKER_DAEMON_ADDRESS"
    set -g DOCKER_DAEMON_ADDRESS "host.docker.internal:2375"
end

if test -z "$DOCKER_PROJECT_NAME"
    echo -e "WARNING: \"DOCKER_PROJECT_NAME\" NOT SET. This might lead to data loss or corruption if you don't verify the minecraft server is off before backing it up!!!"
end

if not test -z "$RCON_HOST"
    if test -z "$RCON_PORT"
        set -g RCON_PORT 25575
    end

    set RCON_PASSWORD (cat /run/secrets/rcon_password | string trim)
end
#!SECTION

#SECTION - Check backup configuration
if test -z "$BACKUP_TYPE"
    set -g BACKUP_TYPE "tarball"
else if not contains -- "$BACKUP_TYPE" "7zip" "duplicate" "tarball"
    echo "Invalid BACKUP_TYPE ($BACKUP_TYPE). Defaulting to 'tarball'"
    set -g BACKUP_TYPE "tarball"
end

if not test -z "$BACKUP_LIMIT" && not contains -- "$BACKUP_LIMIT" "day" "week" "month"
    echo "Invalid BACKUP_LIMIT ($BACKUP_LIMIT). Defaulting to 'day'"
    set -g BACKUP_LIMIT "day"
end

if test -z "$CREATE_PARITY_FILES"
    set -g CREATE_PARITY_FILES false
end
#TODO - Parse docker service names
#!SECTION
#!SECTION

#SECTION - Delay
if not test -z "$RCON_HOST"
    rcon-cli --host "$RCON_HOST" --port "$RCON_PORT" --password "$RCON_PASSWORD" -- "say Server will be backed up after $BACKUP_DELAY. Please finish up with what you're doing!"
    if not test -z "$BACKUP_DELAY"
        sleep -- "$BACKUP_DELAY"
    end
end
#!SECTION

#SECTION Step 1 - Kick all players to turn off the server and yeah
echo "Step 1"
if not test -z "$RCON_HOST"
    echo -e "\tKicking Players."
    rcon-cli --host "$RCON_HOST" --port "$RCON_PORT" --password "$RCON_PASSWORD" -- "kick @a $BACKUP_KICK_MESSAGE"
    if test $status -ne 0
        echo -e "\t\tWARNING: Couldn't kick players"
    else
        echo -e "\t\tKicked Players with Message \"$BACKUP_KICK_MESSAGE\""
    end
else
    echo -e "\t\"RCON_HOST\" was not set, skipping player kicking"
end

if not test -z "$DOCKER_PROJECT_NAME"
    echo -e "\tShutting down docker services"
    docker -H "$DOCKER_DAEMON_ADDRESS" compose -p "$DOCKER_PROJECT_NAME" stop -- $DOCKER_SERVICES #REVIEW this takes EVERYTHING down. and apparently i should add -t 60 or sum
    if test $status -ne 0 #REVIEW - It doesn't execute this when the project name doesn't exist
        echo -e "\t\tFATAL: Couldn't stop docker container(s)." >&2
        exit 1
    else
        echo -e "\t\tStopped Docker Container(s)"
    end
end
#!SECTION

#SECTION Step 2 - Backup
echo "Step 2: Backup"

set DATE_NOW (date "+%Y-%m-%d-%H-%M")
set BACKUP_STORAGE_FOLDER "$BACKUPS_FOLDER/$DATE_NOW"

mkdir -- "$BACKUP_STORAGE_FOLDER"
if test $status -ne 0
    echo -e "\tFATAL: Failed to make backup folder" >&2
    exit 1
else
    echo -e "\tCreated backup directory inside backups folder"
end

if test "$BACKUP_TYPE" = "duplicate"
    cp -a "$DATA_FOLDER/." "$BACKUP_STORAGE_FOLDER"
    if test $status -ne 0
        echo -e "\tFATAL: Couldn't copy data folder!" >&2
        exit 1
    end
else
    set archive_creation_status 0
    if test "$BACKUP_TYPE" = "7zip"
        #REVIEW - I think the user should be able to set their own compression level, no...?
        #REVIEW - In real world stuff, I noticed this doesn't even reach 6gb and only to about 5.5gb. Maybe it should be changed 
        cd "$DATA_FOLDER"
        7z a -t7z -mx=9 -m0=lzma2 -mmemuse=7g -- "$BACKUP_STORAGE_FOLDER/$DATE_NOW.7z" . # Limit to about 7gb of memory,
        set archive_creation_status $status
    else
        tar -cf "$BACKUP_STORAGE_FOLDER/$DATE_NOW.tar" -C "$DATA_FOLDER" .
        set archive_creation_status $status
    end

    if test $archive_creation_status -ne 0
        echo -e "\tFATAL: Failed to create archive!" >&2
        exit 1
    else
        echo -e "\tCreated $BACKUP_TYPE Archive"
    end
end
#!SECTION

#SECTION Step 3 Create parity files in archive's backup folder
if set -l p (string lower -- "$CREATE_PARITY_FILES"); if test "$p" = true; and test "$BACKUP_TYPE" != "duplicate"
    echo "Step 3: Parity file creation"

    cd "$BACKUP_STORAGE_FOLDER"
    set parity_files_creation_status 0
    
    if test "$BACKUP_TYPE" = "7zip"
        par2 c -r10 -q "$DATE_NOW.7z"
        set parity_files_creation_status $status
    else
        par2 c -r10 -q "$DATE_NOW.tar"
        set parity_files_creation_status $status
    end

    if test $parity_files_creation_status -ne 0
        echo -e "\tWARNING: Archive has no parity data. Failed to generate!" >&2
    else
        echo -e "\tParity files created."
    end
end
#!SECTION

echo "Finished creating backup $DATE_NOW."

if not test -z "$BACKUP_LIMIT"
    echo "Now pruning extra backups..."
    prune_old_backups "$BACKUP_LIMIT"
end