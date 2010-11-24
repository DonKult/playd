#!/bin/sh
# License {{{1
#
# Copyright (c) 2009-2010, Aldis Berjoza <aldis@bsdroot.lv>
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
# project email: playd@bsdroot.lv

readonly PLAYD_VERSION='1.15.0'
readonly PLAYD_NAME="${0##*/}"
readonly PLAYD_FILE_FORMATS='mp3|flac|og[agxmv]|wv|aac|mp[421a]|wav|aif[cf]?|m4[abpr]|ape|mk[av]|avi|mpf|vob|di?vx|mpga?|mov|3gp|wm[av]|midi?'
readonly PLAYD_PLAYLIST_FORMATS='plst?|m3u8?|asx|xspf|ram|qtl|wax|wpl'

playd_warn() {	# {{{1
	while [ $# -gt 0 ]; do
		echo "WARN: $1" >&2
		shift
	done
	return 1
}	# 1}}}

playd_die() {	# {{{1
	while [ $# -gt 0 ]; do
		echo "ERR: $1" >&2
		shift
	done
	exit 1
}	# 1}}}

# HOME variable must be defined
[ -z "$HOME" ] && playd_die 'You are homeless. $HOME not defined'

readonly OS=`uname`
case $OS in
*BSD )	readonly ESED='sed -E' ;;
* )		readonly ESED='sed -r' ;;
esac

readonly PLAYD_HOME="${XDG_CONFIG_HOME:-"$HOME/.config"}/playd"
# users config file
[ -f "$PLAYD_HOME/playd.conf" ] && . "$PLAYD_HOME/playd.conf"

PLAYD_PIPE="${PLAYD_PIPE:-"$PLAYD_HOME/playd.fifo"}"
PLAYD_PLAYLIST="${PLAYD_PLAYLIST:-"$PLAYD_HOME/playlist.plst"}"
PLAYD_FAV_PLAYLIST="${PLAYD_FAV_PLAYLIST:-"$PLAYD_HOME/favourite.plst"}"
PLAYD_LOCK="${PLAYD_LOCK:-"$PLAYD_HOME/mplayer.lock"}"

PAGER=${PAGER:-more}
FORMAT_SHORTNAMES=${FORMAT_SHORTNAMES:-yes}
FORMAT_SPACES=${FORMAT_SPACES:-yes}

# to customise mplayers command line set PLAYD_MPLAYER_USER_OPTIONS environment variable
readonly MPLAYER_CMD_GENERIC="$PLAYD_MPLAYER_USER_OPTIONS -msglevel all=-1 -nomsgmodule -idle -input file=$PLAYD_PIPE"
readonly MPLAYER_CMD="mplayer $MPLAYER_CMD_GENERIC"
readonly MPLAYER_SND_ONLY_CMD="mplayer -vo null $MPLAYER_CMD_GENERIC"
readonly PLAYD_HELP="man 1 playd"

playd_put() {	# {{{1
	# put argv into pipe
	case "$1" in
		'loadlist' | 'loadfile' )
			[ -f "$2" ] \
				&& PLAYD_APPEND=1 \
				|| { playd_warn "File doesn't exist:" "  $2"; return 1; }
			;;
	esac

	playd_check \
		&& { playd_clean; [ "$1" != 'quit' ] && { playd_start; echo "$*" >> "$PLAYD_PIPE"; }; } \
		|| echo "$*" >> "$PLAYD_PIPE"
	return 0
}	# 1}}}

playd_check() {	# {{{1
	# check if playd daemon is running and return pid
	# returns 0 if daemon ain't running
	[ -f "$PLAYD_LOCK" ] && { local PID=$(pgrep -g `cat $PLAYD_LOCK` -n mplayer); return $PID; }
	return 0
}	# 1}}}

playd_clean() {	#{{{1
	# clean files after playd
	playd_check && rm -f "$PLAYD_PIPE" "$PLAYD_LOCK" "$PLAYD_HOME"/*.tmp
}	# 1}}}

playd_start() {	# {{{1
	# start daemon
	playd_check && {
		[ -p "$PLAYD_PIPE" ] || { mkfifo "$PLAYD_PIPE" || playd_die "Can't create \"$PLAYD_PIPE\""; }
		cd /
		[ $NOVID -eq 0 ] \
			&& local MPLAYER_RUN_CMD="$MPLAYER_CMD" \
			|| local MPLAYER_RUN_CMD="$MPLAYER_SND_ONLY_CMD"

		{ $MPLAYER_RUN_CMD > /dev/null 2> /dev/null & } \
			&& echo "$$" > "$PLAYD_LOCK" \
			|| playd_die 'Failed to start mplayer'
		cd - > /dev/null 2> /dev/null
	}
}	# 1}}}

playd_stop() {	# {{{1
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
}	# 1}}}

playd_mk_playlist() {	# {{{1
	# make playlist from directory
	# arguments:
	# $1 - dir to make list
	# $1 and $fileName must be double quoted to avoid
	#   problems with filenames that contain special characters
	ls "$1" | while read FILENAME; do
		if [ -f "$1/$FILENAME" ]; then
			local FNAME="$1/$FILENAME"
			echo "${FILENAME##*.}" | grep -q -i -E -e "^(${PLAYD_FILE_FORMATS})$" \
				&& echo "$FNAME" >> "$PLAYD_PLAYLIST.tmp" \
				|| { file -ib "$FNAME" | grep -q -E -e '^(audio|video)' && echo "$FNAME" >> "$PLAYD_PLAYLIST.tmp"; }
		elif [ -d "$1/$FILENAME" ]; then
			playd_mk_playlist "$1/$FILENAME"
		else
			playd_die "What the hell: \"$1/$FILENAME\""
		fi
	done
}	# 1}}}

playd_fullpath() {	# {{{1
	# echo full path of file/dir
	case "$1" in
	/* ) echo "$1" | sed -e 's#//#/#g';;
	* ) echo "`pwd`/$1" | sed -e 's#//#/#g';;
	esac
}	# 1}}}

playd_playlist_add() {	# {{{1
	#add entry to playlist
	# arg1 = playlist item
	[ $PLAYD_APPEND -eq 1 ] \
		&& echo "$1" >> "$PLAYD_PLAYLIST" \
		|| echo "$1" > "$PLAYD_PLAYLIST"
	[ $NOPLAY -eq 0 ] && playd_put 'loadfile' "$1" $PLAYD_APPEND
}	# 1}}}

playd_playlist_addlist() {	# {{{1
	# add list to playlist
	# arg1 = playlist item
	[ $PLAYD_APPEND -eq 1 ] \
		&& cat "$1" >> "$PLAYD_PLAYLIST" \
		|| cat "$1" > "$PLAYD_PLAYLIST"
	[ $NOPLAY -eq 0 ] && playd_put 'loadlist' "$1" $PLAYD_APPEND
}	# 1}}}

playd_randomise() {	# {{{1
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
}	# 1}}}

playd_import() {	# {{{1
	# this function will import playlists
	# arg1 filename (with full path) to playlist
	[ -f "$1" ] || return 1
	case `echo "${1##*.}" | tr [A-Z] [a-z]` in
	ram )	grep -v -e '^.$' "$1" > "$PLAYD_PLAYLIST.tmp" || playd_warn "Empty playlist. Skipping" ;;
	plst )	cat "$1" > "$PLAYD_PLAYLIST.tmp" ;;

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
}	# 1}}}

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
	if [ "$OS" = 'FreeBSD' ]; then
		procstat -f $pid | sed -n '/ 4 v r r-------/s#.* /#/#p'
	else
#		lsof -p $pid | grep -e '4r' | sed -e 's#.* /#/#'
		lsof -p $pid | sed -n '/4r/s#.* /#/#p'
	fi
} # 1}}}

playd_current_file_escaped() { # {{{1
	# prints current file name, that mplayer is playing.
	# this function prepares string for awk (adds escape sequences)
	playd_current_file | sed -e 's#[/.)(*{}+?$&^-]#\\&#g' -e 's#\[#\\\[#g' -e 's#\]#\\\]#g'
} # 1}}}

playd_cat_playlist() { # {{{1
	if [ -f "$PLAYD_PLAYLIST" ]; then
		if [ $FORMAT_SHORTNAMES = 'yes' -o $FORMAT_SHORTNAMES = 'YES' ]; then
				playd_longcat_playlist \
					| $ESED \
						-e 's#/.*/##' \
						-e 's#_# #g' \
						-e 's#^[ ]*##' \
						-e 's# ?- ?[0-9]{1,2} ?- ?# - #' \
						-e 's#-[0-9]{2}\.# - #' \
						-e "s#\.($PLAYD_FILE_FORMATS)\$##" \
						-e 's#\|  (([0-9][ -]?)?[0-9]{1,2}( - |\. |-|\.| ))?#|  #' \
						-e 's#\|\* (([0-9][ -]?)?[0-9]{1,2}( - |\. |-|\.| ))?#|* #'
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
		awk "/^`playd_current_file_escaped`"'$/ { printf("%0'$PADDING'd|* %s\n", NR, $0); next } /.*/ { printf("%0'$PADDING'd|  %s\n", NR, $0) }' "$PLAYD_PLAYLIST"
	else
		playd_warn "Default playlist doesn't exist."
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
	'again' )							playd_put 'seek' 0 1 ;;
	'append' )							playd_warn "$1 should be 1st argument. Ignoring" ;;
	'cat' )								playd_cat_playlist ;;
	'cat-favourites' | 'catfav' )		cat "$PLAYD_FAV_PLAYLIST" ;;
	'filename' | 'fname' )				playd_current_file ;;
	'help' | '--help' | '-h' )			$PLAYD_HELP ;;
	'list' | 'ls' )						playd_cat_playlist | $PAGER ;;
	'list-favourites' | 'lsfav' )		$PAGER "$PLAYD_FAV_PLAYLIST" ;;
	'longcat' | 'lcat' )				playd_longcat_playlist ;;
	'longlist' | 'llist' )				playd_longcat_playlist | $PAGER ;;
	'mute' )							playd_put 'mute' ;;
	'next' )							playd_put 'pt_step' 1 ;;
	'noplay' )							NOPLAY=1 ;;
	'pause' )							playd_put 'pause' ;;
	'playlist' )						NOPLAY=0; playd_put 'loadlist' "$PLAYD_PLAYLIST" $PLAYD_APPEND ;;
	'previous' | 'prev' )				playd_put 'pt_step' -1 ;;
	'rmlist' )							rm -f "$PLAYD_PLAYLIST" ;;
	'rnd' | 'randomise' )				mv `playd_randomise "$PLAYD_PLAYLIST"` "$PLAYD_PLAYLIST" ;; 
	'status' )							playd_check && echo 'playd is not running' || echo "playd is running. PID: $?" ;;
	'stop')								playd_stop ;;
	'switch-audio' | 'sw-audio' )		playd_put 'switch_audio' ;;
	'switch-subtitles' | 'sw-subs' )	playd_put 'sub_select' ;;

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
		[ -f "$2" ] \
			&& { playd_playlist_add "$(playd_fullpath "$2")"; shift; } \
			|| playd_warn "\"$2\" directory. Skipping"
		;;

	'subtitles' | 'subs' )
		[ -f "$2" ] \
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

	'start' \
	| 'restart' )
		[ "$1" = 'restart' ] && playd_stop
		[ "$2" = 'novid' ] && NOVID=1 || NOVID=0
		shift $NOVID
		playd_start
		;;

	'loop' )
		if [ -n $2 ]; then
			playd_put 'loop' $2
			shift
		else
			if [ $2 = 'forever' ]; then
				playd_put 'loop' 0
				shift
			else
				playd_put 'loop' -1
			fi
		fi
		;;

	'play' )
		if [ $2 ]; then
			if [ $2 -ne 0 ]; then
				while [ -n "$2" ]; do
					if [ $2 -gt 0 ]; then
						playd_put 'loadfile' "`awk '{ if (NR == '$2') print $0 }' "$PLAYD_PLAYLIST"`" $PLAYD_APPEND
						shift
					else
						break
					fi
				done
			else
				playd_warn "$1 needs numeric argument. Ignoring"
			fi
		else
			playd_warn "$1 needs numeric argument. Ignoring"
		fi
		;;

	'seek' )
		if [ $2 ]; then
			MATCH=0
			[ $3 = 'abs' -o $3 = 'absolute' ] && MATCH=2
			[ $3 = '%' -o $3 = 'percent' ] && MATCH=1
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

	'cd' \
	| 'dvd' )
		[ "$1" = 'cd' ] && MEDIA='cdda://' || MEDIA='dvdnav://'
		if [ $2 ]; then
			if [ $2 -gt 0 ]; then
				while [ $2 ]; do
					[ $2 -gt 0 ] \
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
		if [ -n $2 ]; then
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
		playd_playlist_add "$1" ;;

	'file' | * )
		[ "$1" = 'file' ] && shift
		FILENAME=`playd_fullpath "$1"`

		if [ -f "$FILENAME" ]; then
			echo "${1##*.}" | grep -q -i -E -e "^(${PLAYD_FILE_FORMATS})$" \
				&& playd_playlist_add "$FILENAME" \
				|| { file -ib "$FILENAME" | grep -q -E -e '^(audio|video)' && playd_playlist_add "$FILENAME"; } \
				|| { echo "${1##*.}" | grep -q -i -E -e "^($PLAYD_PLAYLIST_FORMATS)$" && playd_import "$FILENAME"; } \
				|| playd_warn "\"$FILENAME\" doesn't seam to be valid file for playback. Ignoring" "to override use:" "  $PLAYD_NAME nocheck $FILENAME"
		elif [ -d "$FILENAME" ]; then
			rm -f "$PLAYD_PLAYLIST.tmp"
			playd_mk_playlist "$FILENAME"
			playd_playlist_addlist "$PLAYD_PLAYLIST.tmp"
		else
			playd_warn "\"$FILENAME\" doesn't seam to be valid file for playback. Ignoring" 'to override use:' "  $PLAYD_NAME nocheck $FILENAME"
		fi
		;;

	esac

	shift
done

exit 0
# vim: set ts=4 sw=4 foldminlines=3 fdm=marker:
