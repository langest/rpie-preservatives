#!/usr/bin/env bash
###############################################################################
# Scans the es_systems_path file to find the extensions of  rom files. This
# data is then used to build an exclusion list, so we don't end up syncing
# large rom files by mistake.
###############################################################################
getSystemsExtensionExclusions() {
    mapfile -t < <( \
        grep -P "<name>[^<]*<" ${es_systems_path} \
            | sed 's/<[\/]*name>//g' \
            | sed 's/ //g' )
    SYSTEMS=("${MAPFILE[@]}")

    mapfile -t < <( \
        grep -P "<extension>[^<]*<" ${es_systems_path} \
            | sed 's/[ ]*<[\/]*extension>//g' \
            | sed "s/[ ]*\./,/g" \
            | sed "s/^,/*.{/" \
            | sed "s/$/}/" )
    GAME_EXTENSIONS=("${MAPFILE[@]}")

    for i in "${!SYSTEMS[@]}"; do
        if [ "${SYSTEMS[$i]}" = "$SYSTEM" ]; then
           SYSTEM_INDEX="$i"
        fi
    done
}

###############################################################################
# uses rclone to sync the remote directory with the local file system for the
# system we are running. 
###############################################################################
syncDirectory() {
    local system_path="${roms_path}/${SYSTEM}"
    local exclude="${GAME_EXTENSIONS[$SYSTEM_INDEX]}"
    local source=""
    local dest=""
    local states="state*,oops,0*,"
    local patch_files="ips,ups,bps,"

    if [ "$COMMAND" = "download" ]; then
        source="${rclone_drive}/${SYSTEM}"
        dest="${system_path}"
    else
        source="${system_path}"
        dest="${rclone_drive}/${SYSTEM}"
    fi

    if [ "$sync_save_states" = "$TRUE" ]; then
        states=""
    fi

    if [ "$sync_patch_files" = "$TRUE" ]; then
        patch_files=""
    fi

    echo ""
    echo "Syncing $SYSTEM save files..."
    echo ""
    rclone \
	sync -v -L "${source}" "${dest}" -P \
        --filter "- *.{${states}${patch_files}xml,txt,chd,DS_Store}" \
        --filter "- media/**" \
        --filter "- images/" \
        --filter "- videos/" \
	--filter "+ mame*/nvram/*.nv" \
	--filter "+ mame*/nvram/*/nvram" \
	--filter "+ mame*/hi/**" \
        --filter "- mame*/**" \
	--filter "- fbneo*/**" \
        --filter "- **sd.raw" \
        --filter "- **.m3u" \
        --filter "- **.bin" \
        --filter "- **.raw" \
        --filter "- **.bak" \
        --filter "- **.rom" \
        --filter "- **.ngp" \
        --filter "- **.CCD" \
        --filter "- **.ccd" \
        --filter "- **.SUB" \
        --filter "- **.sub" \
        --filter "- **.html" \
        --filter "- **.wav" \
        --filter "- **.iso" \
        --filter "- **.mp3" \
        --filter "- **.mds" \
        --filter "- **.png" \
        --filter "- **.jpeg" \
        --filter "- **.jpg" \
        --filter "- **scummvm/** TODO HERE" \
        --filter "- **dinosaur_planet/rom" \
        --filter "- Mupen64plus/**" \
        --filter "- User/Cache**" \
        --filter "- User/Config**" \
        --filter "- User/Logs**" \
        --filter "- PSP/SYSTEM/**" \
        --filter "- $exclude" 
}

###############################################################################
# Checks whether a system is valid to sync or not. If valid, syncs the system.
# Skips syncing on systems that don't support it (mostly mame). This function
# is not complete, as I don't have roms for all the systems supported by
# retroarch, and I don't plan on emulating them all either.
###############################################################################
syncIfValidSystem() {
    case $SYSTEM in 
        retropie) echo "skipping retropie directory" ;;
        kodi) echo "skipping kodi" ;;
	pc) echo "skipping pc" ;;
        scummvm) echo "skipping scummvm" ;;
        ports) echo "skipping ports" ;;
	#TODO: implement for specific ports
        *) syncDirectory ;;
    esac
}

###############################################################################
# Prints instructions.
###############################################################################
printUsage() {
    echo "Usage: rpie-preservatives.sh <command> <system name> <emulator> <rom path> <full command>"
    echo "  command is required. Must be either 'upload' or 'download'."
    echo "  system name is the name of the system in es_systems.cfg (eg:  nes,atari2600,gba,etc)."
    echo "  emulator: the core name that was launched (eg: lr-stella,lr-fceumm,etc)"
    echo "  rom path: full path to the rom file"
    echo "  full command: the full command line used to launch the emulator."
}

###############################################################################
# prints a warning that all saves will be synced. Displays instructions on
# cancelling the script and provides a 5 second timer to allow cancelling.
###############################################################################
printAllSystemWarning() {
    echo "No system passed in. All saves will be ${COMMAND}ed. (Ctl-C to abort)"
    printCountdown
}

###############################################################################
# prints a list of the current settings before performing the sync.
###############################################################################
printConfig() {
    echo "executing with current settings: "
    echo "  rclone_drive: $rclone_drive"
    echo "  roms_path: $roms_path"
    echo "  sync_save_states: $sync_save_states"
    echo ""
}

###############################################################################
# prints a countdown before proceeding.
###############################################################################
printCountdown() {
    printf "syncing in 5"
    sleep 1
    printf "\rsyncing in 4"
    sleep 1
    printf "\rsyncing in 3"
    sleep 1
    printf "\rsyncing in 2"
    sleep 1
    printf "\rsyncing in 1"
    sleep 1
    printf "\rsyncing in 0"
    printf "\r*** Syncing ***"

}


###############################################################################
# prints an error messages for missing files/folders from config file.
###############################################################################
printSettingNotFoundError(){
    echo "   ${1} not found. Ensure the value for ${1} in rpie-settings.cfg is correct."
}

###############################################################################
# prints an error message for bad boolean values from config file.
###############################################################################
printSettingBooleanError() {
    echo "   ${1} has a bad value. Valid values are '${TRUE}' and '${FALSE}'. Ensure ${1} in rpie-settings.cfg is correct."
}

###############################################################################
# Verifies the values in the settings file to ensure the values are valid.
# Prints out any errors it finds.
###############################################################################
verifySettings() {
    echo "verifying settings."
    local result=0

    if ! [ -d "${roms_path}" ]; then 
        printSettingNotFoundError "roms_path"
        result=1
    fi
    
    if ! [ -f "${es_systems_path}" ]; then
        printSettingNotFoundError "es_systems_path"
        result=1
    fi

    sync_save_states=`echo "$sync_save_states" | awk '{print tolower($0)}'`
    if [[ "$sync_save_states" != "$TRUE" ]] && [[ "$sync_save_states" != "$FALSE" ]]; then
        printSettingBooleanError "sync_save_states"
        result=1
    fi
    
    sync_patch_files=`echo "$sync_patch_files" | awk '{print tolower($0)}'`
    if [[ "$sync_patch_files" != "$TRUE" ]] && [[ "$sync_patch_files" != "$FALSE" ]]; then
        printSettingBooleanError "sync_patch_files"
        result=1
    fi
    
    if ! [[ "$rclone_drive" =~ ^.+:.+$ ]]; then
        echo "   rclone_drive does not appear to be valid. Must be in the format remote:DESTINATION. Correct value in rpie-settings.cfg"
        result=1
    fi

    return $result
}


###############################################################################
# prints the missing config file message.
###############################################################################
printMissingConfig() {
    local workingDir=`pwd`
    echo "rpie-settings.cfg could not be found. Ensure rpie-settings.cfg exist in ${workingDir}"
    exit 1
}

COMMAND=$1
SYSTEM=$2
EMULATOR=$3
ROM_PATH=$4
RUN_COMMAND=$5

GREEN="\e[92m"
RED="\e[91m"
PLAIN="\e[39m"
TRUE="true"
FALSE="false"

if test -a "/opt/retropie/configs/all/rpie-settings.cfg"; then
    . /opt/retropie/configs/all/rpie-settings.cfg
    verifySettings
    if [ $? -eq 0 ]; then
        echo "Settings valid!"
        getSystemsExtensionExclusions

        if [ $# -eq 0 ]; then
            printUsage
        elif [ $# -eq 1 ]; then
            if [ "$1" = "upload" ] || [ "$1" = "download" ]; then
                printAllSystemWarning
                for i in "${!SYSTEMS[@]}"; do
                    SYSTEM_INDEX="$i"
                    SYSTEM="${SYSTEMS[$i]}"
                    syncIfValidSystem
                done
            else
                printUsage
            fi
        else
            syncIfValidSystem
        fi
    else
        exit 1
    fi
else
    printMissingConfig
fi

