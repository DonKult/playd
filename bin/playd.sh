#!/bin/sh
# License {{{1
#
# Copyright (c) 2009-2011, Aldis Berjoza <graudeejs@gmail.com>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
# * Redistributions of source code must retain the above copyright
#   notice, this list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above
#   copyright notice, this list of conditions and the following disclaimer
#   in the documentation and/or other materials provided with the
#   distribution.
# * Neither the name of the  nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# 1}}}

# repository:       https://github.com/graudeejs/playd

readonly PLAYD_VERSION='1.22.3'
# dependancies:
#   * mplayer   (multimedia/mplayer)
#   * tagutil   (audio/tagutil) [Optional, needed if you want playd info]
#     supported alternatives: id3info, id3v2
#   * jot       (Included in FreeBSD)

readonly PLAYD_NAME="${0##*/}"
readonly PLAYD_FILE_FORMATS='mp3|flac|og[agxmv]|wv|aac|mp[421a]|wav|aif[cf]?|m4[abpr]|ape|mk[av]|avi|mpf|vob|di?vx|mpga?|mov|flv|3gp|wm[av]|(m2)?ts|ac3'
readonly PLAYD_PLAYLIST_FORMATS='plst?|m3u8?|asx|xspf|ram|qtl|wax|wp'


playd_warn() {  # {{{1
    while [ $# -gt 0 ]; do
        echo "WARN: $1" >&2
        shift
    done
    return 1
}   # 1}}}

playd_die() {   # {{{1
    while [ $# -gt 0 ]; do
        echo "ERR: $1" >&2
        shift
    done
    Exit 1
}   # 1}}}

# HOME variable must be defined
[ -z "$HOME" ] && playd_die 'You are homeless. $HOME not defined'

readonly PLAYD_HOME="${XDG_CONFIG_HOME:-"$HOME/.config"}/playd"

# on Debian alike systems a better default than more exists
if which sensible-pager >/dev/null 2>&1; then
    PAGER='sensible-pager'
fi

# users config file
[ -f "$PLAYD_HOME/playd.conf" ] && . "$PLAYD_HOME/playd.conf"

if [ "$COLOR_OUTPUT" = "1" ]; then
    readonly SET_COLOR="\x1b[33;1m"
    readonly CLEAR_COLOR="\x1b[0m"
fi
# user overridable options
readonly FORMAT_SHORTNAMES="${FORMAT_SHORTNAMES:-"yes"}"
readonly FORMAT_SPACES="${FORMAT_SPACES:-"yes"}"
readonly PAGER="${PAGER:-"more"}"
readonly PLAYD_FAV_PLAYLIST="${PLAYD_FAV_PLAYLIST:-"$PLAYD_HOME/favourite.plst"}"
readonly PLAYD_MPLAYER_USER_OPTIONS="${PLAYD_MPLAYER_USER_OPTIONS:-""}"
readonly PLAYD_PIPE="${PLAYD_PIPE:-"$PLAYD_HOME/playd.fifo"}"
readonly PLAYD_PLAYLIST="${PLAYD_PLAYLIST:-"$PLAYD_HOME/playlist.plst"}"
readonly PLAYD_POS="${PLAYD_POS:-"$PLAYD_HOME/playlist.pos"}"
readonly TEMP="${TEMP:-"/tmp"}"

# to customise mplayers command line set PLAYD_MPLAYER_USER_OPTIONS environment variable
readonly MPLAYER_CMD_GENERIC="$PLAYD_MPLAYER_USER_OPTIONS -msglevel all=-1 -nomsgmodule -idle -input file=$PLAYD_PIPE"
readonly MPLAYER_CMD="mplayer $MPLAYER_CMD_GENERIC"
readonly MPLAYER_SND_ONLY_CMD="mplayer -vo null $MPLAYER_CMD_GENERIC"
readonly PLAYD_HELP="man 1 playd"

readonly OS=`uname`

case $OS in
    'FreeBSD' )
        ESED='sed -E'
        FETCH="fetch"
        ;;
    * )
        FETCH="wget"
        ESED='sed -r'
        ;;
esac
playd_file_exists() { # {{{1
    # check if the given file exists, either as real file
    # or as a (non-broken) link
    test -e "$1" && test -f "$1" -o -L "$1" && return 0 || return 1
}   #1}}}

playd_put() {   # {{{1
    # put argv into pipe
    if [ "$1" = 'quit' ]; then
        playd_check || echo "$@" >> "$PLAYD_PIPE"
        return 0
    fi

    if playd_check; then playd_start; fi

    case "$(echo "$1" | cut -d' ' -f 2)" in
        'loadlist' | 'loadfile' )
            playd_file_exists "$2" && PLAYD_APPEND=1 \
                || { playd_warn "File doesn't exist:" "  $2"; return 1; }
            printf "%s '%s' %d\n" "$1" "$(echo "$2" | sed -e "s#'#\\\'#g")" "$3" >> "$PLAYD_PIPE"
            ;;
        *)
            echo "$@" >> "$PLAYD_PIPE"
    esac

    return 0
}   # 1}}}

playd_check() { # {{{1
    # check if playd daemon is running and return pid
    # returns 0 if daemon ain't running
    return `ps -wwax | grep -e " mplayer .* -idle -input file=$PLAYD_PIPE$" | grep -E -v -e ' grep ' | awk '{print $1}'`
}   # 1}}}

playd_clean() { #{{{1
    # clean files after playd
    playd_check && rm -f "$PLAYD_PIPE" "$PLAYD_HOME"/*.tmp
}   # 1}}}

playd_start() { # {{{1
    # start daemon
    playd_check && {
        [ -p "$PLAYD_PIPE" ] || { mkfifo "$PLAYD_PIPE" || playd_die "Can't create \"$PLAYD_PIPE\""; }
        cd /
        [ $NOVID -eq 0 ] \
            && local MPLAYER_RUN_CMD="$MPLAYER_CMD" \
            || local MPLAYER_RUN_CMD="$MPLAYER_SND_ONLY_CMD"

        { exec $MPLAYER_RUN_CMD > /dev/null 2> /dev/null & } \
            || playd_die 'Failed to start mplayer'
        cd - > /dev/null 2> /dev/null
    }
}   # 1}}}

playd_stop() {  # {{{1
    # stop playd daemon
    playd_check || {
        PID=$?
        playd_put 'quit'
        sleep 1 # give mplayer 1 second to quit
        for i in 1 2 3; do
            kill -s 0 $PID 2> /dev/null || { playd_clean; return; }
            kill $PID 2> /dev/null
            sleep 1
        done
        kill -s 0 $PID 2> /dev/null && playd_die "Can't kill mplayer slave with pid $PID"
    }
    playd_clean
}   # 1}}}

playd_mk_playlist() {   # {{{1
    # make playlist from directory
    # arguments:
    # $1 - dir to make list
    # $1 and $fileName must be double quoted to avoid
    #   problems with filenames that contain special characters
    if [ -d "$1" ]; then
        find -L "$1" -name '.git' -prune -o -type f -print | grep -E -i -e "(${PLAYD_FILE_FORMATS})$" | sort >> "$PLAYD_PLAYLIST.tmp"
    elif playd_file_exists "$1"; then
        echo "${1##*.}" | grep -q -i -E -e "^(${PLAYD_FILE_FORMATS})$" \
            && echo "$1" >> "$PLAYD_PLAYLIST.tmp" \
            || { file -ib "$1" | grep -q -E -e '^(audio|video)' && echo "$1" >> "$PLAYD_PLAYLIST.tmp"; }
    else
        playd_die "What the hell: \"$1\""
    fi
}   # 1}}}

playd_fullpath() {  # {{{1
    # echo full path of file/dir
    case "$1" in
    /* ) echo "$1" | sed -e 's#//#/#g' -e 's#/*$##' ;;
    * ) echo "`pwd`/$1" | sed -e 's#//#/#g' -e 's#/*$##' ;;
    esac
}   # 1}}}

playd_playlist_add() {  # {{{1
    #add entry to playlist
    # arg1 = playlist item
    playd_file_exists "$1" || { playd_warn "File doesn't exist:" "  $1"; return 1; }
    [ $PLAYD_APPEND -eq 1 ] \
        && echo "$1" >> "$PLAYD_PLAYLIST" \
        || { echo "$1" > "$PLAYD_PLAYLIST"; rm -f "$PLAYD_POS"; }
    [ $NOPLAY -eq 0 ] && playd_put 'loadfile' "$1" $PLAYD_APPEND
}   # 1}}}

playd_playlist_addlist() {  # {{{1
    # add list to playlist
    # arg1 = playlist item
    test -f "$1" || { playd_warn "Playlist doesn't exist:" "  $1"; return 1; }
    [ $PLAYD_APPEND -eq 1 ] \
        && cat "$1" >> "$PLAYD_PLAYLIST" \
        || { cat "$1" > "$PLAYD_PLAYLIST"; rm -f "$PLAYD_POS"; }
    [ $NOPLAY -eq 0 ] && playd_put 'loadlist' "$1" $PLAYD_APPEND
}   # 1}}}

playd_randomise() { # {{{1
    # this function will randomise default playlist
    # arg1 = list to randomize
    # at the end echos new list name
    if [ -f "$1" ]; then
        local LIST=`echo "$1" | sed 's#^.*/##'`
        rm -f "$PLAYD_HOME/$LIST.tmp"
        [ ! -d "$PLAYD_HOME/rand" ] \
            && mkdir "$PLAYD_HOME/rand" \
            || rm -fR "$PLAYD_HOME/rand"/*

        local I=0
        cat "$1" | while read ITEM; do
            echo "$ITEM" > "$PLAYD_HOME/rand/$I"
            I=$(($I + 1))
        done

        I=$(awk 'END { print NR }' "$1")

        local J=
        local ID=
        for J in $(jot $I $(($I - 1)) 0 -1); do
            ID=$(jot -r 1 0 $J)
            cat "$PLAYD_HOME/rand/$ID" >> "$PLAYD_HOME/$LIST.tmp"
            mv "$PLAYD_HOME/rand/$J" "$PLAYD_HOME/rand/$ID" 2> /dev/null > /dev/null
        done
        rm -Rf "$PLAYD_HOME/rand"/*
        echo "$PLAYD_HOME/$LIST.tmp"
        return 0
    fi
    playd_warn "File doesn't exist:" "$1"
    return 1
}   # 1}}}

playd_import() {    # {{{1
    # this function will import playlists
    # arg1 filename (with full path) to playlist
    playd_file_exists "$1" || return 1
    case `echo "${1##*.}" | tr [A-Z] [a-z]` in
    ram )   grep -v -e '^.$' "$1" > "$PLAYD_PLAYLIST.tmp" || playd_warn "Empty playlist. Skipping" ;;
    plst )  cat "$1" > "$PLAYD_PLAYLIST.tmp" ;;

    pls )
        { grep -i -e '^file' "$1" || playd_warn "Empty playlist. Skipping"; } \
            | sed -e 's/file[0-9]*=//I' > "$PLAYD_PLAYLIST.tmp"
        ;;

    m3u|m3u8 )
         grep -v -E -e '^(.|#.*)$' "$1" > "$PLAYD_PLAYLIST.tmp" || playd_warn "Empty playlist. Skipping"
        ;;

    asx|wax )
        { grep -i -E -e '<ref href=".*".?/>' "$1" || playd_warn "Empty playlist. Skipping"; } \
            | sed -e 's/^.*href="//I' -e 's/".*$//' > "$PLAYD_PLAYLIST.tmp"
        ;;

    xspf )
        { grep -i -e '<location>.*</location>' "$1" || playd_warn "Empty playlist. Skipping"; } \
            | sed -e 's#^.*<location>##I' -e 's#</location>.*$##I' -e 's#file://##I' > "$PLAYD_PLAYLIST.tmp"
        ;;

    qtl )
        { grep -i -e 'src=".*"' || playd_warn "Empty playlist. Skipping"; } \
            | sed -e 's/.*src="//I' -e 's/".*$//' > "$PLAYD_PLAYLIST.tmp"
        ;;

    wpl )
        { grep -i -E -e '<media src=".*".?/>' "$1" || playd_warn "Empty playlist. Skipping"; } \
            | sed -e 's/^.*<media src="//I' -e 's/".*$//' > "$PLAYD_PLAYLIST.tmp"
        ;;

    * )
        playd_warn "Sorry `echo "${1##*.}" | tr [A-Z] [a-z]` is unsupported playlist type. Ignoring"
        return 1
        ;;
    esac

    [ $? -eq 0 ] || return 1

    playd_playlist_addlist "$PLAYD_PLAYLIST.tmp"
}   # 1}}}

playd_time2s() { # {{{1
    # convert human readable time to seconds
    # arg1 time in human readable form (for example 2m30s)
    echo "$1" | sed -e 's/y/*31536000+/' -e 's/M/*2592000+/' -e 's/w/*604800+/' -e 's/d/*86400+/' -e 's/h/*3600+/' -e 's/m/*60+/' -e 's/s//' -e 's/\+$//' | bc -l
} # 1}}}

playd_current_file() { # {{{1
    # prints current file name, that mplayer is playing
    playd_check
    pid=$?
    [ $pid -ne 0 ] || return
    # XXX "head -n 1" is really bad hack to fix playd
    local FILE=''
    if [ "$OS" = 'FreeBSD' ]; then
        FILE="$(procstat -f $pid | sed -n '/[0-9] v r r-------/s#.* /#/#p' | head -n 1)"
    else
        FILE="$(lsof -p $pid | sed -n '/[0-9]r[ ]\+\(VR\|R\)EG /s#.* /#/#p' | head -n 1)"
    fi
    # if the file is in an annex find the file linking to it to get a proper name
    if expr match "$FILE" '^.*/\.git/annex/.*$' >/dev/null 2>&1; then
        local DIR="$(echo "$FILE" | sed -n 's#^\(.\+\)/\.git/annex/.*$#\1#p')"
        find -L "$DIR" -name '.git' -prune -o -samefile "$FILE" -print -quit
    else
        echo "$FILE"
    fi
} # 1}}}

playd_current_file_escaped() { # {{{1
    # prints current file name, that mplayer is playing.
    # this function prepares string for awk (adds escape sequences)
    playd_current_file | sed -e 's#[/.)(*{}+?$&^-]#\\&#g' -e 's#\[#\\\[#g' -e 's#\]#\\\]#g' | tr -d "\n"
} # 1}}}

playd_cat_playlist() { # {{{1
    if [ -f "$PLAYD_PLAYLIST" ]; then
        if [ $FORMAT_SHORTNAMES = 'yes' -o $FORMAT_SHORTNAMES = 'YES' ]; then
                playd_longcat_playlist \
                    | awk '
{
    sub(/\/.*\//, "", $0)
    gsub(/_/, " ", $0)
    gsub(/   [ ]*/, " ", $0)
    sub(/\|  ([12]-)?[0-9][0-9]\.?[ ]?-?[ ]?/, "|  ", $0)
    sub(/\|\* ([12]-)?[0-9][0-9]\.?[ ]?-?[ ]?/, "|* ", $0)
    print $0
}' | $ESED -e 's/\.('$PLAYD_FILE_FORMATS')$//I'
        else
            if [ $FORMAT_SPACES = 'yes' -o $FORMAT_SPACES = 'YES' ]; then
                playd_longcat_playlist | sed -e 's#/.*/##' -e 's#_# #g'
            else
                playd_longcat_playlist | sed -e 's#/.*/##'
            fi
        fi
    else
        playd_warn "Default playlist doesn't exist."
    fi
} # 1}}}

playd_longcat_playlist() { # {{{1
    if [ -f "$PLAYD_PLAYLIST" ]; then
        local PADDING=`awk 'END { print length(NR) }' $PLAYD_PLAYLIST`
        playd_check
        if [ $? -ne 0 ]; then
            awk "/^`playd_current_file_escaped`"'$/ { printf("%0'$PADDING'd|* %s\n", NR, $0); next } { printf("%0'$PADDING'd|  %s\n", NR, $0) }' "$PLAYD_PLAYLIST"
        else
            if [ -f "$PLAYD_POS" ]; then
                POS=`cat "$PLAYD_POS"`
                awk 'NR == '$POS' { printf("%0'$PADDING'd|S %s\n", NR, $0); next }; { printf("%0'$PADDING'd|  %s\n", NR, $0) }' "$PLAYD_PLAYLIST"
            else
                awk '{ printf("%0'$PADDING'd|  %s\n", NR, $0) }' "$PLAYD_PLAYLIST"
            fi
        fi
    else
        playd_warn "Default playlist doesn't exist."
    fi
} # 1}}}

playd_ls() { # {{{1
    if [ -f "$PLAYD_PLAYLIST" ]; then
        local PADDING=`awk 'END { print length(NR) }' $PLAYD_PLAYLIST`
        local ITEMS=`awk 'END { print NR }' $PLAYD_PLAYLIST`
        playd_check
        if [ $? -ne 0 ]; then
            local CURRENT_FILE="`playd_current_file_escaped`"
            local POS=`awk 'BEGIN { showed=0 }; /'"$CURRENT_FILE"'/ && showed == 0 { print NR; showed = 1 }' "$PLAYD_PLAYLIST"`
            local POS_MARKER="*"
        else
            if [ -f "$PLAYD_POS" ]; then
                local POS=`cat "$PLAYD_POS"`
                local POS_MARKER="S"
            else
                local POS=0
            fi
        fi

        local SCREEN_W=`tput cols`
        local SCREEN_H=`tput lines`
        local LS_PRE_POS=$(($SCREEN_H / 4))
        LS_PRE_POS=${LS_PRE_POS:-0}
        SCREEN_H=${SCREEN_H:-24}
        POS=${POS:-1}
        [ $LS_PRE_POS -ge $POS ] && LS_PRE_POS=$(($POS - 1))
        local LS_POST_POS=$(($SCREEN_H - 2 - $LS_PRE_POS))
        [ $(($LS_POST_POS + $POS)) -gt $ITEMS ] && LS_PRE_POS=$(($LS_PRE_POS + $POS + $LS_POST_POS - $ITEMS))
        awk '
NR >= '$(($POS-$LS_PRE_POS))' && NR <= '$(($POS+$LS_POST_POS))' {
        sub(/\/.*\//, "", $0)
        gsub(/_/, " ", $0)
        gsub(/   [ ]*/, " ", $0)
        sub(/^([12]-)?[0-9][0-9]\.?[ ]?-?[ ]?/, "", $0)

        if (NR != '$POS') {
            OUT=sprintf("%0'$PADDING'd|  %s", NR, $0)
        } else {
            OUT=sprintf("%0'$PADDING'd|'$POS_MARKER$SET_COLOR' %s'$CLEAR_COLOR'", NR, $0)
        }

        print substr(OUT, 1, '$SCREEN_W')
}
' "$PLAYD_PLAYLIST" | $ESED -e 's/\.('$PLAYD_FILE_FORMATS')$//I'
    else
        playd_warn "Default playlist doesn't exist."
    fi
} # }}}

playd_save_pos() { # {{{1
    playd_check || {
        if [ -f "$PLAYD_PLAYLIST" ]; then
            CURRENT_SONG=`playd_current_file_escaped`
            if [ "$CURRENT_SONG" != '' ]; then
                awk 'BEGIN { printed=0 }; /'"$CURRENT_SONG"'/ && printed == 0 { print NR; printed=1 }' "$PLAYD_PLAYLIST" > "$PLAYD_POS"
                return 0
            fi
        fi
        return 1
    }
} # 1}}}

Exit() { # {{{1
    playd_save_pos
    exit $1
} # 1}}}

playd_edit_playlist() { # {{{1
    # arg1 playlist to edit
    # on Debian alike systems a better default(!) than vi exists
    if which sensible-editor >/dev/null 2>&1; then
        EDITOR='sensible-editor'
    fi
    ${EDITOR:-vi} "$1"
    playd_clean_playlist "$1"
    # TODO: add checks
    #playd_put 'loadlist' "$PLAYD_PLAYLIST" "0"
} # 1}}}

playd_clean_playlist() { #{{{1
    # arg1 - playlist to clean
    rm -f "$1.tmp"
    cat "$1" | while read item; do
        [ -r "$item" ] && echo "$item"
    done > "$1.tmp"
    mv "$1.tmp" "$1"
} # 1}}}

playd_info() { #{{{1
    if which tagutil >/dev/null 2>&1; then
        tagutil "`playd_current_file`"
    elif which id3info >/dev/null 2>&1; then
        id3info "`playd_current_file`"
    elif which id3v2 >/dev/null 2>&1; then
        id3v2 -l "`playd_current_file`"
    else
        playd_die 'You need to install tagutil, id3info or id3v2 to use this command'
    fi
} # 1}}}

# checking for mplayer
[ "`which mplayer`" ] || playd_die 'mplayer not found'
[ -d "$PLAYD_HOME" ] || { mkdir -p "$PLAYD_HOME" || playd_die "Can't create \"$PLAYD_HOME\""; }

NOVID=0
NOPLAY=0
[ "$1" = 'append' ] \
    && { PLAYD_APPEND=1; shift; } \
    || PLAYD_APPEND=0

# check command line arguments
[ $# -eq 0 ] && $PLAYD_HELP
while [ $# -gt 0 ]; do
    case "$1" in
    'again' )                           playd_put 'seek' 0 1 ;;
    'append' )                          playd_warn "$1 should be 1st argument. Ignoring" ;;
    'cat' )                             playd_cat_playlist ;;
    'cat-favourites' | 'catfav' )       cat "$PLAYD_FAV_PLAYLIST" ;;
    'clean' )                           playd_clean_playlist "$PLAYD_PLAYLIST" ;;
    'clean-favourite' | 'cleanfav' )    playd_clean_playlist "$PLAYD_FAV_PLAYLIST" ;;
    'edit' )                            playd_edit_playlist "$PLAYD_PLAYLIST" ;;
    'edit-favourite' | 'editfav' )      playd_edit_playlist "$PLAYD_FAV_PLAYLIST" ;;
    'filename' | 'fname' )              playd_current_file ;;
    'grep' )                            playd_cat_playlist | egrep -i "$2"; shift ;;
    'help' | '--help' | '-h' )          $PLAYD_HELP ;;
    'info' )                            playd_info ;;
    'lgrep' )                           playd_longcat_playlist | egrep -i "$2"; shift ;;
    'list' )                            playd_cat_playlist | $PAGER ;;
    'list-favourites' | 'lsfav' )       $PAGER "$PLAYD_FAV_PLAYLIST" ;;
    'longcat' | 'lcat' )                playd_longcat_playlist ;;
    'longlist' | 'llist' )              playd_longcat_playlist | $PAGER ;;
    'ls' )                              playd_ls ;;
    'mute' )                            playd_put 'mute' ;;
    'next' )                            playd_put 'pt_step' 1 ;;
    'noplay' )                          NOPLAY=1 ;;
    'pause' )                           playd_put 'pause' ;;
    'playlist' )                        NOPLAY=0; playd_put 'loadlist' "$PLAYD_PLAYLIST" $PLAYD_APPEND ;;
    'previous' | 'prev' )               playd_put 'pt_step' -1 ;;
    'rmlist' )                          rm -f "$PLAYD_PLAYLIST" ;;
    'rnd' | 'randomise' )               mv `playd_randomise "$PLAYD_PLAYLIST"` "$PLAYD_PLAYLIST" ;;
    'save-state' | 'save' )             playd_save_pos || playd_warn "Failed to save sate." ;;
    'status' )                          playd_check && echo 'playd is not running' || echo "playd is running. PID: $?" ;;
    'switch-audio' | 'sw-audio' )       playd_put 'switch_audio' ;;
    'switch-subtitles' | 'sw-subs' )    playd_put 'sub_select' ;;
    'version')                          echo "$PLAYD_NAME v$PLAYD_VERSION" ;;

    'stop' )
        playd_save_pos
        playd_stop
        Exit
        ;;

    'cmd' )
        [ -n "$2" ] \
            && { playd_put "$2"; shift; } \
            || playd_warn "$1 needs argument to pass to mplayer. Ignoring"
        ;;

    'sort' )
        if [ -f "$PLAYD_PLAYLIST" ]; then
            [ "$2" = 'reverse' -o "$2" = 'rev' ] && { SORT_CMD='sort -r'; shift; } || SORT_CMD='sort'
            $SORT_CMD "$PLAYD_PLAYLIST" | uniq > "$PLAYD_PLAYLIST.tmp"; mv "$PLAYD_PLAYLIST.tmp" "$PLAYD_PLAYLIST"
        fi
        ;;

    'nocheck' )
        playd_file_exists "$2" \
            && { playd_playlist_add "$(playd_fullpath "$2")"; shift; } \
            || playd_warn "\"$2\" directory. Skipping"
        ;;

    'subtitles' | 'subs' )
        playd_file_exists "$2" \
            && { playd_put 'sub_load' "$2"; shift; } \
            || playd_warn "\"$2\" isn't subtitle file. Skipping"
        ;;

    'favourite' | 'fav' )
        playd_current_file >> "$PLAYD_FAV_PLAYLIST"
        sort "$PLAYD_FAV_PLAYLIST" > "$PLAYD_FAV_PLAYLIST.tmp"
        uniq "$PLAYD_FAV_PLAYLIST.tmp" > "$PLAYD_FAV_PLAYLIST"
        rm "$PLAYD_FAV_PLAYLIST.tmp"
        ;;

    'not-favourite' | 'notfav' | '!fav' )
        if [ -f "$PLAYD_FAV_PLAYLIST" ]; then
            awk '/^'"`playd_current_file_escaped`"'$/ { next }; /.*/ { print $0 }' "$PLAYD_FAV_PLAYLIST" > "$PLAYD_FAV_PLAYLIST.tmp"
            mv "$PLAYD_FAV_PLAYLIST.tmp" "$PLAYD_FAV_PLAYLIST"
        fi
        ;;

    'play-favourites' | 'playfav' )
        FN=`playd_randomise "$PLAYD_FAV_PLAYLIST"` \
            && { mv $FN "$PLAYD_PLAYLIST"; playd_put 'loadlist' "$PLAYD_PLAYLIST" 0; }
        ;;

    'restart' )
        playd_stop
        [ "$2" = 'novid' ] && NOVID=1 || NOVID=0
        shift $NOVID
        playd_start
        ;;

    'loop' )
        if [ -n "$2" ]; then
            playd_put 'loop' $2
            shift
        else
            if [ "$2" = 'forever' ]; then
                playd_put 'loop' 0
                shift
            else
                playd_put 'loop' -1
            fi
        fi
        ;;

    'start' )
        [ "$2" = 'novid' ] && NOVID=1 || NOVID=0
        shift $NOVID
        playd_start
        if [ -f "$PLAYD_PLAYLIST" ]; then
            playd_put 'set_property' 'pause' '1'
            playd_put 'pausing_keep_force loadlist' "$PLAYD_PLAYLIST" 0
            if [ -f "$PLAYD_POS" ]; then
                POS=`cat "$PLAYD_POS"`
                [ "$POS" -gt 1 ] && playd_put 'pausing_keep_force pt_step' $(($POS - 1))
            fi
            playd_put 'pause'
        else
            playd_warn "Default playlist doesn't exist"
            rm -f "$PLAYD_POS"
        fi
        ;;

    'play' )
        if [ -n "$2" ]; then
            while [ -n "$2" ]; do
                if [ "$2" -gt 0 ]; then
                    playd_put 'loadfile' "`awk '{ if (NR == '$2') print $0 }' "$PLAYD_PLAYLIST"`" $PLAYD_APPEND
                else
                    playd_warn "$1 needs a numeric argument, but it got '$2'. Ignoring"
                fi
                shift
            done
        else
            playd_warn "$1 needs at least one numeric argument. Ignoring"
        fi
        ;;

    'seek' )
        if [ "$2" ]; then
            MATCH=0
            [ "$3" = 'abs' -o "$3" = 'absolute' ] && MATCH=2
            [ "$3" = '%' -o "$3" = 'percent' ] && MATCH=1
            playd_put 'seek' "`playd_time2s $2`" $MATCH
            [ $MATCH -ne 0 ] && shift
            shift
        else
            playd_warn "$1 needs numeric argument. Ignoring"
        fi
        ;;

    'jump' )
        if [ -f "$PLAYD_PLAYLIST" ]; then
            ITEM_COUNT=`awk 'END { print NR }' $PLAYD_PLAYLIST`
            PLAYD_APPEND=0
            NUMBER=$2
            [ "$2" = 'rnd' -o "$2" = 'random' ] && NUMBER=`jot -r 1 0 $ITEM_COUNT`
            if [ $NUMBER -gt 0 -a $NUMBER -le $ITEM_COUNT ]; then
                awk 'NR >= '"$NUMBER"' { print $0 }' "$PLAYD_PLAYLIST"  > "$PLAYD_PLAYLIST.tmp"
                awk 'NR < '"$NUMBER"' { print $0 }' "$PLAYD_PLAYLIST"  >> "$PLAYD_PLAYLIST.tmp"
                playd_put 'loadlist' "$PLAYD_PLAYLIST.tmp" $PLAYD_APPEND
                shift
            else
                playd_warn "Invalid or out or range Playlist Item number."
            fi
        else
            playd_warn "Default playlist doesn't exist."
        fi
        ;;


    # BUG IN THIS CODE
    'cd' \
    | 'dvd' )
        [ "$1" = 'cd' ] && MEDIA='cdda://' || MEDIA='dvd://'
        if [ "$2" ]; then
            if [ "$2" -gt 0 ]; then
                while [ "$2" ]; do
                    [ "$2" -gt 0 ] \
                        && { playd_playlist_add "$MEDIA$2"; shift; } \
                        || break
                done
            fi
        else
            playd_playlist_add "$MEDIA"
        fi
        ;;

    'audio-delay' \
    | 'brightness' \
    | 'contrast' \
    | 'gamma'  \
    | 'hue' \
    | 'saturation' \
    | 'volume' | 'vol' )
        if [ -n "$2" ]; then
            [ "$3" = 'abs' -o "$3" = 'absolute' ] && MATCH=1 || MATCH=0
            COMMAND="$1"
            [ "$1" = 'vol' ] && COMMAND='volume'
            [ "$1" = 'audio-delay' ] && COMMAND='audio_delay'
            playd_put "$COMMAND" "$2" $MATCH
            shift $((1 + $MATCH))
        else
            playd_warn "$1 needs at least numeric argument. Ignoring"
        fi
        ;;

    *'://'* )
        if echo "${1##*.}" | grep -q -i -E -e "^($PLAYD_PLAYLIST_FORMATS)$" > /dev/null; then
            URL="$1"
            FILENAME="$TEMP/$$.`basename $1`.tmp"
            $FETCH -o "$FILENAME" "$URL"
            playd_playlist_addlist "$FILENAME"
            sleep 1
            rm -f "$FILENAME"
        else
            playd_playlist_add "$1"
        fi
        ;;


    'file' | * )
        [ "$1" = 'file' ] && shift
        FILENAME=`playd_fullpath "$1"`

        if [ -d "$FILENAME" ]; then
            rm -f "$PLAYD_PLAYLIST.tmp"
            playd_mk_playlist "$FILENAME"
            playd_playlist_addlist "$PLAYD_PLAYLIST.tmp"
        elif playd_file_exists "$FILENAME"; then
            echo "${1##*.}" | grep -q -i -E -e "^(${PLAYD_FILE_FORMATS})$" \
                && playd_playlist_add "$FILENAME" \
                || { file -ib "$FILENAME" | grep -q -E -e '^(audio|video)' && playd_playlist_add "$FILENAME"; } \
                || { echo "${1##*.}" | grep -q -i -E -e "^($PLAYD_PLAYLIST_FORMATS)$" && playd_import "$FILENAME"; } \
                || playd_warn "\"$FILENAME\" doesn't seam to be valid file for playback. Ignoring" "  to override use:" "  $PLAYD_NAME nocheck $FILENAME"
        else
            playd_warn "\"$FILENAME\" seams to be neither a directory not a file. Ignoring" '  to override use:' "  $PLAYD_NAME nocheck $FILENAME"
        fi
        ;;

    esac

    shift
done

Exit 0
# vim: set ts=4 sw=4 expandtab foldminlines=3 fdm=marker:
