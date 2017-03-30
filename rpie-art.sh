#!/usr/bin/env bash
# rpie-art.sh
#
# TODO:
# - check info.txt integrity (invalid characters: ';')

if ! source /opt/retropie/lib/inifuncs.sh ; then
    echo "ERROR: \"inifuncs.sh\" file not found! Aborting..." >&2
    exit 1
fi

scriptdir="$(dirname "$0")"
scriptdir="$(cd "$scriptdir" && pwd)"
readonly REPO_FILE="$scriptdir/repositories.txt"
readonly SCRIPT_REPO="$(head -1 "$scriptdir/repositories.txt" | cut -d' ' -f1)"
readonly BACKTITLE="rpie-art: installing art on your RetroPie."
readonly ART_DIR="$HOME/RetroPie/art"
readonly ROMS_DIR="$HOME/RetroPie/roms"
readonly CONFIG_DIR="/opt/retropie/configs"
readonly SPLASHSCREEN_EXTRA_REPO="https://github.com/HerbFargus/retropie-splashscreens-extra"
readonly SPLASHSCREEN_EXTRA_DIR="$HOME/RetroPie/splashscreens/retropie-extra"


# dialog functions ##########################################################

function dialogMenu() {
    local text="$1"
    shift
    dialog --no-mouse --backtitle "$BACKTITLE" --menu "$text\n\nChoose an option." 17 75 10 "$@" 2>&1 > /dev/tty
}



function dialogInput() {
    local text="$1"
    shift
    dialog --no-mouse --backtitle "$BACKTITLE" --inputbox "$text" 9 70 "$@" 2>&1 > /dev/tty
}



function dialogYesNo() {
    dialog --no-mouse --backtitle "$BACKTITLE" --yesno "$@" 15 75 2>&1 > /dev/tty
}



function dialogMsg() {
    dialog --no-mouse --backtitle "$BACKTITLE" --msgbox "$@" 20 70 2>&1 > /dev/tty
}



function dialogInfo {
    dialog --infobox "$@" 8 50 2>&1 >/dev/tty
}

# end of dialog functions ###################################################


# menu functions ############################################################

function main_menu() {
    local cmd=( dialog --no-mouse --backtitle "$BACKTITLE" 
        --title " Main Menu " --cancel-label "Exit" --item-help
        --menu "Update this tool or choose a repository to get art from." 17 75 10 
    )
    local options=( U "Update rpie-art script." "This will update this script and the files in the rpie-art repository." )
    local choice
    local i=1
    local url
    local description

    while read -r url description; do
        options+=( $((i++)) "$url" "$description" )
    done < "$REPO_FILE"

    while true; do
        choice=$( "${cmd[@]}" "${options[@]}" 2>&1 > /dev/tty )

        case "$choice" in 
# TODO: decidir se vou utilizar esse método de update ou criar um scriptmodule
            U)      update_repo "$repo_rpie_art" ;;
            [0-9])  repo_menu "${options[3*choice+1]}" ;;
            *)      break ;;
        esac
    done
}



function repo_menu() {
    if [[ -z "$1" ]]; then
        echo "ERROR: repo_menu(): missing argument." >&2
        exit 1
    fi

    local repo_url="$1"
    local repo=$(basename "$repo_url")
    local repo_dir="$ART_DIR/$repo"

    if ! [[ -d "$repo_dir" ]]; then
        dialogYesNo "You don't have the files from \"$repo_url\".\n\nDo you want to get them now?\n(it may take a few minutes)" \
        || return 1
# TODO: give a better feedback about what's going on (check dialog --gauge)
        dialogInfo "Getting files from \"$repo_url\".\n\nPlease wait..."
        if ! get_repo_art "$repo_url" "$repo_dir"; then
            dialogMsg "ERROR: failed to download (git clone) files from $repo_url\n\nPlease check your connection and try again."
            return 1
        fi
    fi

    local cmd=( dialogMenu "Options for $repo_url repository." )
    local options=(
        U "Update files from remote repository"
        D "Delete local repository files"
        O "Overlay list"
        L "Launching image list"
        S "Scraped image list"
    )
    local choice

    while true; do
        choice=$( "${cmd[@]}" "${options[@]}" )

        case "$choice" in
            U)  update_repo ;;
            D)  delete_local_repo ;;
            O)  art_menu overlay ;;
            L)  art_menu launching ;;
            S)  art_menu scrape ;;
            *)  break ;;
        esac
    done
}



function art_menu() {
    if ! [[ "$1" =~ ^(overlay|launching|scrape) ]]; then
        echo "ERROR: art_menu(): invalid art type \"$1\"."
        exit 1
    fi

    local art_type="$1"
    local infotxt
    local i=1
    local tmp
    local options=()
    local choice

    dialogInfo "Getting $art_type art info for \"$repo\" repository."

    iniConfig '=' '"'

    while IFS= read -r infotxt; do
        tmp="$(grep -l "^$art_type" "$infotxt")"
        tmp="$(dirname "${tmp/#$ART_DIR\/$repo\//}")"
        [[ "$tmp" == "." ]] && continue
        options+=( $((i++)) "$tmp")
    done < <(find "$repo_dir" -type f -name info.txt | sort)

    if [[ ${#options[@]} -eq 0 ]]; then
        dialogMsg "There's no $art_type art in the \"$repo\" repository."
        return 1
    fi

    while true; do
        choice=$(dialogMenu "Games with $art_type art from \"$repo\" repository." "${options[@]}") \
        || break
        infotxt="$ART_DIR/$repo/${options[2*choice-1]}/info.txt"

        case "$art_type" in
            overlay)    install_overlay_menu ;;
            launching)  install_launching_menu ;;
            scrape)     install_scrape_menu ;;
        esac
    done
}



function install_launching_menu() {
    local system="$(get_value system "$infotxt")"
    local game_name="$(get_value game_name "$infotxt")"
    local launching_image="$(get_value launching_image "$infotxt")"
    local sys game image
    local destination_dir="$ROMS_DIR"
    [[ "$game_name" == "_generic" ]] && destination_dir="$CONFIG_DIR/"
    local options=()
    local choice
    local i=1
    declare -Ag images

    oldIFS="$IFS"
    IFS=';'
    for image in $launching_image; do
        images[$i]="$image"
        options+=( $((i++)) "$(basename "$image")" )
    done
    IFS="$oldIFS"
    
    while true; do
        choice=$(dialogMenu "Launching image list for ${game_name}." "${options[@]}") \
        || return
        image="${images[$choice]}"

        image="$(check_file "$image")"
        if [[ -z "$image" ]]; then
            dialogMsg "We had some problem with the file \"$image\"!\n\nUpdate files form remote repository and try again. If the problem persists, report it at \"$repo_url/issues\"."
            return 1
        fi

        show_image "$image"
        # TODO: RECOMEÇAR AQUI
    done
}


# end of menu functions #####################################################


# other functions ###########################################################

function get_repo_art() {
    if [[ -d "$repo_dir/.git" ]]; then
        cd "$repo_dir"
        git fetch --prune
        git reset --hard origin/master > /dev/null
        git clean -f -d
        cd -
    else
        git clone --depth 1 "$repo_url" "$repo_dir" || return 1
    fi
}



function get_value() {
    iniGet "$1" "$2"
    if [[ -n "$3" ]]; then
        echo "$ini_value" | cut -d\; -f1
    else
        echo "$ini_value"
    fi
}



function check_file() {
    local file="$1"
    local remote_file

    if [[ "$file" =~ ^http[s]:// ]]; then
        remote_file="$file"
        file="$(dirname "$infotxt")/$(basename "$remote_file")"
        if ! [[ -f "$file" ]]; then
            dialogInfo "Downloading \"$file\".\n\nPlease wait..."
            curl "$remote_file" -o "$file" || return $?
        fi
    fi

    [[ -f "$file" ]] || return $?
    echo "$file"
}



function show_image() {
    local image="$1"
    local timeout=5

    [[ -f "$image" ]] || return 1

    if [[ -n "$DISPLAY" ]]; then
        feh \
            --cycle-once \
            --hide-pointer \
            --fullscreen \
            --auto-zoom \
            --no-menus \
            --slideshow-delay $timeout \
            --quiet \
            "$image" \
        || return $?
    else
        fbi \
            --once \
            --timeout "$timeout" \
            --noverbose \
            --autozoom \
            "$image" </dev/tty &>/dev/null \
        || return $?
    fi
}


# end of other functions ####################################################


# START HERE ################################################################

if ! [[ -d "$(dirname "$ART_DIR")" ]]; then
    echo "ERROR: $(dirname "$ART_DIR") not found." >&2
    exit 1
fi

mkdir -p "$ART_DIR"

main_menu
echo
