# Strengthened Docker Minecraft Server Backup Creator

I wanted a way to backup a minecraft server with an almost 100% no bitrot for long-term stuffs so I made this.

It's a simple fish shell script that I containerized with docker. It really just compresses the contents of the minecraft data folder using 7zip with LZMA2 level-9 then stores it in the provided backup folder. Or if you want, you can just use tarball or just copy paste the whole folder

**THIS DOES NOT RUN AUTOMATICALLY, IT'S DESIGNED TO BE EXECUTED BY AN EXTERNAL SERVICE**

> *Also, you can technically use this to backup anything...*

## Configuration

These are the possible configurations you can do for your backup service (take [compose.yaml](compose.yaml) as an example)

### RCON Configuration

These are just used to inform people inside the minecraft server if a backup is going to happen or is happening.

|Name|Required|Default Value|
|---|---|---|
|RCON_HOST|||
|RCON_PORT||25575|

### Docker Configuration

These are optional, you can just run the backup service without needing to expose your docker daemon

|Name|Required|Default Value|Notes
|---|:---:|:-:|-|
|DOCKER_DAEMON_ADDRESS||host.docker.internal:2375|You have to enable "expose docker daemon" in Docker Desktop
|DOCKER_PROJECT_NAME|||This comes from Docker, the main container that contains containers. **WARNING: LEAVING THIS BLANK WILL NOT STOP ANY SERVERS AND THE BACKUP WILL STILL BE CREATED.**
|DOCKER_SERVICES|||Leaving this blank will shut down all services of the specified docker project|

### Backup Configuration

|Name|Required|Default Value|Notes
|---|:---:|:--:|-|
|BACKUP_TYPE||tarball|Checkout available values below|
|BACKUP_DELAY|||Blank = instant. Possible values: `5m` (5 minutes) or `5` (5 seconds). Only respected when RCON is set.|
|BACKUP_KICK_MESSAGE|||Blank = kick all players without any message|
|BACKUP_LIMIT|||Blank = Never delete any backups. Checkout available values below.|
|CREATE_PARITY_FILES||false|Parity files are used to repair bitrot. Leave blank/false if you're not planning to archive the backup for long-term storage. **NOT APPLICABLE IF `BACKUP_TYPE` IS SET TO `duplicate`**|

**Possible Values for `BACKUP_TYPE`:**
- `7zip`
  - Pros:
    - Saves disk space
    - Stores the backup into a single file
    - can compress an 8.1GB server into just 3.6GB
  - Cons:
    - Needs around 6GB of usable memory
    - Takes about 7 minutes to compress an 8.1GB server
- `duplicate`
  - Pros:
    - Fastest one
  - Cons:
    - Doesn't store the backup inside a single file
    - **NOT POSSIBLE** to create parity files
- `tarball`
  - Pros:
    - Second fastest one
    - Stores the backup into a single file
  - Cons:
    - No compression happens, an 8GB server would stay as 8GB.

**Possible Values for `BACKUP_LIMIT`:**
- `day`
  - After the day has passed, only keep the most recent backup from that day
- `week`
  - After the week has passed, only keep the most recent backup from that week
- `month`
  - After the month has passed, only keep the most recent backup from that month

### Other Configurations and Information

- Store your RCON password inside a file named `rcon_password.txt`
- Minecraft data folder is mounted as read-only
- Backups folder **MUST** be writable

## How it works

There's 3 steps on what this does. And depending on the option you provided in [compose.yaml](compose.yaml), it will change what the backup script does.

### Step 1 - Shutting down the Docker Compose Server

This assumes that the minecraft server is running on Docker and that there's an exposed tcp daemon port (quite dangerous but yeah). Oh and also the messages only work if you set up RCON properly

- Broadcasts a message to all players before shutting down the server, telling them that the server will perform a backup after `BACKUP_DELAY` (This will only happen if RCON is set)
- Kicks players with the message `BACKUP_KICK_MESSAGE`

### Step 2 - Backup Creation

The action of this step depends on the value of `BACKUP_TYPE`

|BACKUP_TYPE|Action|
|:-:|-|
|7zip|Compresses the whole server into a 7zip archive with LZMA2 and at level-9. Then puts that archive into a folder in the backups folder|
|duplicate|Copies the contents of the data folder into a folder in the backups folder|
|tarball|Puts all the contents of the data folder into a single file. Then puts that file into the backups folder|

`7zip`/`tarball` backups will always be stored in this format:
- Folder `2000-01-01-12-00` (YYYY-MM-DD-HH-MM)
  - File `2000-01-01-12-00.7z` or `2000-01-01-12-00.tar`
  - (if `CREATE_PARITY_FILES` is `true`) Files `2000-01-01-12-00.7z.par2` or `2000-01-01-12-00.tar.par2`

`duplicate` backups will look like this:
- Folder `2000-01-01-12-00` (YYYY-MM-DD-HH-MM)
  - File `server.properties`
  - *Other files from the data folder*

### Step 3 - Parity File Creation

This is only applicable if you set `CREATE_PARITY_FILES` to be `true` in your service definition.

- This creates parity files for your archive, only works with `tarball` or `7zip` backup type.
- Parity files are only useful if you plan on storing your server backups for the long-term or if you have your pc directly inside a large hadron collider.

## Planned Features

|Feature|Status|Date Added|
|-|-|-|
|Run the backup without sending any messages nor delays as long as there's no players active in the server||Nov. 11, 2026|
|Allow backups to be 7zip, tarball, or just copy paste the data folder|Done|Nov. 10, 2026|

> AI was used to review the shell script against this README.md file but not to write it. If you don't believe me, just watch my livestreams on [TikTok](https://tiktok.com/@easyacedthat). I'm against AI writing code, but AI reviewing the code is fine.