#!/bin/sh

# License {{{1

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

# project email: playd@bsdroot.lv
# 1}}}

readonly PLAYD_VERSION='1.9.0'
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

readonly PLAYD_HOME="$HOME/.config/playd"
readonly PLAYD_PIPE="$PLAYD_HOME/fifo"
readonly PLAYD_PLAYLIST="$PLAYD_HOME/playlist.plst"
readonly PLAYD_LOCK="$PLAYD_HOME/lock"

# to customise mplayers command line set PLAYD_MPLAYER_USER_OPTIONS environment variable
readonly MPLAYER_CMD_GENERIC="$PLAYD_MPLAYER_USER_OPTIONS -really-quiet -idle -input file=$PLAYD_PIPE"
readonly MPLAYER_CMD="mplayer $MPLAYER_CMD_GENERIC"
readonly MPLAYER_SND_ONLY_CMD="mplayer -vo null $MPLAYER_CMD_GENERIC"

playd_help() {	#{{{1
	# print help
	cat << EOF
$PLAYD_NAME (playd.sh) v$PLAYD_VERSION
by Aldis Berjoza
http://wiki.bsdroot.lv/playd
http://aldis.git.bsdroot.lv/playd.sh
project e-mail: playd@bsdroot.lv

Special thanks to:
  * DutchDaemon
  * blah
  * john_doe
from forums.freebsd.org for few lines of sh


COMMANDS (long names):
  append
  audio-delay value [ --absolute ]
  cd [ track ]
  cmd 'mplayer command'
  brightness value [ --absolute 
  contrast value [ --absolute ]
  dvd [ track ]
  file [ file | directory ]
  gamma value [ --absolute ]
  hue value [ --absolute ]
  list
  longlist
  mute
  next
  nocheck file
  pause
  play item1 [item2] ...
  playlist
  randomise
  restart [ --console ] [ --nofork ]
  rmlist
  seek value [ --absolute | --present ]
  sarution value [ --absolute ]
  start [ --console ] [ --nofork ]
  status
  subtitles file
  stop
  switch-audio
  switch-subtitle
  volume value [ --absolute ]

see playd(1) for more info
EOF
}	#1}}}

playd_put() {	# {{{1
	# put argv into pipe
	playd_check \
		&& { playd_clean; [ "$1" != "quit" ] && { playd_start && echo "$*" >> "$PLAYD_PIPE"; }; } \
		|| echo "$*" >> "$PLAYD_PIPE"
}	# 1}}}

playd_check() {	# {{{1
	# check if playd daemon is running and return pid
	# returns 0 if daemon ain't running
	[ -f "$PLAYD_LOCK" ] \
		&& local pid=$(pgrep -g `cat $PLAYD_LOCK` -n mplayer) \
		&& return $pid
	return 0
}	# 1}}}

playd_clean() {	#{{{1
	# clean files after playd
	rm -f "$PLAYD_PLAYLIST.tmp"
	playd_check && rm -f "$PLAYD_PIPE" "$PLAYD_LOCK"
}	# 1}}}

playd_start() {	# {{{1
	# start daemon
	# possible arguments:
	# console novid (order doesn't matter)
	playd_check && {
		[ -p "$PLAYD_PIPE" ] || { mkfifo "$PLAYD_PIPE" || playd_die "Can't create \"$PLAYD_PIPE\""; }
		cd /
		[ $NOVID -eq 0 ] \
			&& local mplayer_run_cmd="$MPLAYER_CMD" \
			|| local mplayer_run_cmd="$MPLAYER_SND_ONLY_CMD"

		if [ $CONSOLE -eq 0 ]; then
			{ ${mplayer_run_cmd} > /dev/null 2> /dev/null & } \
				&& echo "$$" > "$PLAYD_LOCK" \
				|| playd_die 'Failed to start mplayer'
		else
			local dbg_pipe="$PLAYD_HOME/playd_debug.pipe"
			mkfifo "$dbg_pipe"
			{ exec ${mplayer_run_cmd} 2>&1 > "$dbg_pipe" & } \
				&& echo "$$" > "$PLAYD_LOCK" \
				|| playd_die 'Failed to start mplayer'
			cat "$dbg_pipe"
			playd_clean
			rm -f "$dbg_pipe"
			exit
		fi
		cd -
	}
}	# 1}}}

playd_stop() {	# {{{1
	# stop playd daemon
	playd_check || {
		pid=$?
		playd_put 'quit'
		sleep 1 # give mplayer 1s to quit
		kill -s 0 $pid 2> /dev/null && {
			kill $pid 2> /dev/null
			sleep 1
			kill -s 0 $pid 2> /dev/null && {
				kill $pid 2> /dev/null
				sleep 1
				kill -s 0 $pid 2> /dev/null && {
					kill -s KILL $kill_pid 2> /dev/null
					sleep 1
					kill -s 0 $pid 2> /dev/null && playd_die "Can't kill mplayer slave with pid $kill_pid"
				}
			}
		}
	}
	playd_clean
}	# 1}}}

playd_mk_playlist() {	# {{{1
	# make playlist from directory
	# arguments:
	# $1 - dir to make list
	# $1 and $fileName must be double quoted to avoid
	#   problems with filenames that contain special characters
	ls "$1" | while read fileName; do
		if [ -f "$1/$fileName" ]; then
			local fname="$1/$fileName"
			echo "${fileName##*.}" | grep -q -i -E -e "^(${PLAYD_FILE_FORMATS})$" \
				&& echo "$fname" >> "$PLAYD_PLAYLIST.tmp" \
				|| { file -ib "$fname" | grep -q -E -e '^(audio|video)' && echo "$fname" >> "$PLAYD_PLAYLIST.tmp"; }
		elif [ -d "$1/$fileName" ]; then
			playd_mk_playlist "$1/$fileName"
		else
			playd_die "What the hell: \"$1/$fileName\""
		fi
	done
}	# 1}}}

playd_match() {	# {{{1
	# playd match takes at least 4 arguments.
	# argument count must be even
	# arg 1 is key we need to find
	# arg 2 is what we return if we don't find key
	#---
	# next argument is what we return when we find key
	# next argument is quoted list of possible keys
	#---
	# etc
	#=======
	# check it's usage in source (especially where we want to set volume)
	if [ $# -ge 4 ]; then
		if [ $(($# % 2)) -eq 0 ]; then
			local mkey="$1" # search for key
			local errVal="$2" # return if not found
			while [ $# -gt 0 ]; do
				shift 2
				for ckey in $2; do
					[ "$mkey" = "$ckey" ] && { echo "$1"; return; }
				done
			done
			echo "$errVal"
		else
			playd_die 'playd_match takes even number of arguments'
		fi
	else
		playd_die 'playd_match takes at least 4 arguments'
	fi
}	# 1}}}

playd_fullpath() {	# {{{1
	# echo full path of file/dir
	# should be used as function
	case "$1" in
		/* ) echo "$1";;
		* ) echo "`pwd`/$1";;
	esac
}	# 1}}}

playd_playlist_add() {	# {{{1
	#add entry to playlist
	# arg1 = playlist item
	playd_put "loadfile '$1' $playd_append"
	[ $playd_append -eq 1 ] \
		&& echo "$*" >> "$PLAYD_PLAYLIST" \
		|| echo "$*" > "$PLAYD_PLAYLIST"
	playd_append=1
}	# 1}}}

playd_randomise() {	# {{{1
	# this function will randomise default playlist
	rm -f "$PLAYD_PLAYLIST.tmp"
	[ ! -d "$PLAYD_HOME/rand" ] \
		&& mkdir "$PLAYD_HOME/rand" \
		|| rm -fR "$PLAYD_HOME/rand"/*

	i=0
	cat "$PLAYD_PLAYLIST" | while read item; do
		echo "$item" > "$PLAYD_HOME/rand/$i"
		i=$(($i + 1))
	done
	
	i=$(awk 'END { print NR }' "$PLAYD_PLAYLIST")

	for j in $(jot $i $(($i - 1)) 0 -1); do
		id=$(jot -r 1 0 $j)
		cat "$PLAYD_HOME/rand/$id" >> "$PLAYD_PLAYLIST.tmp"
		mv "$PLAYD_HOME/rand/$j" "$PLAYD_HOME/rand/$id" 2> /dev/null > /dev/null
	done
	mv "$PLAYD_PLAYLIST.tmp" "$PLAYD_PLAYLIST"
	rm -Rf "$PLAYD_HOME/rand"/*
}	# 1}}}

playd_import() {	# {{{1
	# this function will import playlists
	# arg1 filename (with full path) to playlist
	[ -f "$1" ] || return 1
	case `echo "${1##*.}" | tr [A-Z] [a-z]` in
		pls )
			{ grep -i -e '^file' "$1" || playd_warn "Empty playlist. Skipping"; } | sed -e 's/file[0-9]*=//I' > "$PLAYD_PLAYLIST.tmp"
		;;

		ram )
			grep -v -e '^.$' "$1" > "$PLAYD_PLAYLIST.tmp" || playd_warn "Empty playlist. Skipping"
		;;

		m3u|m3u8 )
			 grep -v -E -e '^(.|#.*)$' "$1" > "$PLAYD_PLAYLIST.tmp" || playd_warn "Empty playlist. Skipping"
		;;

		asx|wax )
			{ grep -i -E -e '<ref href=".*".?/>' "$1" || playd_warn "Empty playlist. Skipping"; } | sed -e 's/^.*href="//I' -e 's/".*$//' > "$PLAYD_PLAYLIST.tmp"
		;;

		xspf )
			{ grep -i -e '<location>.*</location>' "$1" || playd_warn "Empty playlist. Skipping"; } | sed -e 's#^.*<location>##I' -e 's#</location>.*$##I' -e 's#file://##I' > "$PLAYD_PLAYLIST.tmp"
		;;

		plst )
			cat "$1" > "$PLAYD_PLAYLIST.tmp"
		;;

		qtl )
			{ grep -i -e 'src=".*"' || playd_warn "Empty playlist. Skipping"; } | sed -e 's/.*src="//I' -e 's/".*$//' > "$PLAYD_PLAYLIST.tmp"
		;;

		wpl )
			{ grep -i -E -e '<media src=".*".?/>' "$1" || playd_warn "Empty playlist. Skipping"; } | sed -e 's/^.*<media src="//I' -e 's/".*$//' > "$PLAYD_PLAYLIST.tmp"
		;;

		* )
			playd_warn "Sorry `echo "${1##*.}" | tr [A-Z] [a-z]` is unsupported playlist type. Ignoring"
			return 1
		;;
	esac

	[ $? -eq 0 ] || return 1

	[ $playd_append -eq 0 ] \
		&& cp -f "$PLAYD_PLAYLIST.tmp" "$PLAYD_PLAYLIST" \
		|| cat "$PLAYD_PLAYLIST.tmp" >> "$PLAYD_PLAYLIST"
	playd_put "loadlist '$PLAYD_PLAYLIST' $playd_append"
	playd_append=1
}	# 1}}}

playd_time2s() { # {{{1
	# convert human readable time to seconds
	# arg1 time in human readable form (for example 2m30s)
	echo "$1" | sed -e 's/y/*31536000+/' -e 's/M/*2592000+/' -e 's/w/*604800+/' -e 's/d/*86400+/' -e 's/h/*3600+/' -e 's/m/*60+/' -e 's/s//' -e 's/\+$//' | bc -l
} # 1}}}

# checking for mplayer
[ "$(which mplayer)" ] || playd_die 'mplayer not found'

[ -d "$PLAYD_HOME" ] || { mkdir -p "$PLAYD_HOME" || playd_die "Can't create \"$PLAYD_HOME\""; }

[ $# -eq 0 ] && playd_help

CONSOLE=0
NOVID=0

playd_append=$(playd_match "$1" 0 1 'append --append -a')
[ $playd_append -eq 1 ] && shift

# check command line arguments
while [ $# -gt 0 ]; do
	case "$1" in
		'append' | '--append' | '-a' )
			playd_warn "$1 should be 1st argument. Ignoring"
		;;

		'help' | '--help' | '-h')
			playd_help
		;;

		'stop' | '--stop' | '-q')
			playd_stop
		;;

		'start' | '--start' \
		| 'restart' | '--restart' | '-R' )
			[ $(playd_match "$1" '0' '1' 'restart --restart -R') ] && playd_stop
			NOVID=$(playd_match "$2" '0' '1' 'novid --novid')
			CONSOLE=$(playd_match "$2" '0' '1' 'console --console')
			shift $(($NOVID + $CONSOLE))
			playd_start $match1 $match2
		;;

		'list' | '--list' | '-l' )
			[ -f "$PLAYD_PLAYLIST" ] \
				&& sed -e 's#^.*/##' -e 's#_# #g' -E -e 's#^(([0-9][ -]?)?[0-9]{1,2}( - |\. |-|\.| ))?##' -e 's#^[ ]*##' -e 's# ?- ?[0-9]{1,2} ?- ?# - #' -e 's#-[0-9]{2}\.# - #' -E -e "s#\.($PLAYD_FILE_FORMATS)\$##" "$PLAYD_PLAYLIST" | awk '{ print NR "|\t" $0 }' | more \
				|| playd_warn "Default playlist doesn't exist."
		;;

		'--longlist' | 'longlist' | 'llist' | '--llist' | '-L' )
			[ -f "$PLAYD_PLAYLIST" ] \
				&& awk '{ print NR "|\t" $0 }' "$PLAYD_PLAYLIST" | more \
				|| playd_warn "Default playlist doesn't exist."
		;;

		# seems buggy
		# I think there's mplayer bug
		# after using playd next or playd seek, playd play doesn't work well (if at all)
		'play' | '--play' | '-p' )
			if [ $2 ]; then
				if [ $2 -ne 0 ]; then
					while [ -n "$2" ]; do
						[ $2 -gt 0 ] \
							&& { playd_put `awk '{ if (NR == '$2' ) item = $0 } END { print "loadfile " "\""item"\" '$playd_append'" }' "$PLAYD_PLAYLIST"`; shift; playd_append=1; } \
							|| break
					done
				else
					playd_warn "$1 needs numeric argument. Ignoring"
				fi
			else
				playd_warn "$1 needs numeric argument. Ignoring"
			fi
		;;

		'playlist' | '--playlist' | '-P' )
			if [ -f "$PLAYD_PLAYLIST" ]; then
				playd_put "loadlist '$PLAYD_PLAYLIST' $playd_append"
				playd_append=1
			else
				playd_warn "Default playlist doesn't exist."
			fi
		;;

		'rmlist' | '--rmlist' )
			rm -f "$PLAYD_PLAYLIST"
		;;

		'seek' | '--seek' | '-s' )
			if [ $2 ]; then
				match=$(playd_match "$3" 0 2 'abs --absolute absolute' 1 '% --percent percent')
				playd_put "seek `playd_time2s $2` $match"
				[ $match -ne 0 ] && shift
				shift
			else
				playd_warn "$1 needs numeric argument. Ignoring"
			fi
		;;

		'next' | '--next' | '-n' )
			playd_put "seek 100 1"
		;;

		'status' | '--status' )
			playd_check \
				&& echo 'playd is not running' \
				|| echo "playd is running. PID: $?"
		;;

		'cd' | 'cdda' | '--cd' | '-c' \
		| 'dvd' | '--dvd' | '-d' )
			media=$(playd_match $1 '0' 'cdda://' 'cd cdda --cd -c' 'dvdnav://' 'dvd --dvd -d')
			if [ $2 ]; then
				if [ $2 -gt 0 ]; then
					while [ $2 ]; do
						[ $2 -gt 0 ] \
							&& { playd_playlist_add "${media}$2"; shift; } \
							|| break
					done
				fi
			else
				playd_playlist_add "$media"
			fi
		;;

		'cmd' | '--cmd' )
			[ -n "$2" ] \
				&& { playd_put "$2"; shift; } \
				|| playd_warn "$1 needs argument to pass to mplayer. Ignoring"
		;;

		'nocheck' | '--nocheck' )
			[ -f "$2" ] \
				&& { playd_playlist_add "$(playd_fullpath "$2")"; shift; } \
				|| playd_warn "\"$2\" directory. Skipping"
		;;

		'--subtitles' | 'subtitles' | '--subs' | 'subs' | '-S' )
			[ -f "$2" ] \
				&& { playd_put "sub_load '$2'"; shift; } \
				|| playd_warn "\"$2\" isn't subtitle file. Skipping"
		;;

		'brightness' | '--brightness' \
		| 'contrast' | '--contrast' \
		| 'gamma' | '--gamma' \
		| 'hue' | '--hue' \
		| 'saturation' | '--saturation' \
		| 'volume' | '--volume' | 'vol' | '-V' | '--vol' \
		| '--audio-delay' | 'audio-delay' )
			if [ -n $2 ]; then
				match=$(playd_match "$3" 0 1 'abs --absolute absolute')
				playd_put "$(playd_match "$1" "$1" \
					'volume' 'vol -V --vol volume --volume' \
					'audio_delay' '--audio-delay audio-delay') \
					$2 $match"
				shift $((1 + $match))
			else
				playd_warn "$1 needs at least numeric argument. Ignoring"
			fi
		;;

		'mute' | '--mute' | '-m' \
		| 'pause' | '--pause' | '-z' \
		| '--switch-audio' | 'switch-audio' | '--sw-audio' | 'sw-audio' \
		| '--switch-subtitles' | 'switch-subtitles' | '--sw-subs' | 'sw-subs' )
			playd_put "$(playd_match "$1" "$1" \
				'mute' 'mute --mute -m' \
				'pause' 'pause --pause -z' \
				'switch_audio' '--switch-audio switch-track --sw-audio sw-audio' \
				'sub_select' '--switch-subtitles switch-subtitles --sw-subs sw-subs')"
		;;

		'rnd' | '--rnd' | '--randomise' | 'randomise' )
			playd_randomise
		;;

		*'://'* )
			playd_playlist_add "$1"
		;;

		'file' | '--file' | '-f' | * )
			[ $(playd_match "$1" 0 1 'file --file -f') -eq 1 ] && shift
			fileName=$(playd_fullpath "$1")

			if [ -f "$fileName" ]; then
				echo "${1##*.}" | grep -q -i -E -e "^(${PLAYD_FILE_FORMATS})$" \
					&& playd_playlist_add "$fileName" \
					|| { file -ib "$fileName" | grep -q -E -e '^(audio|video)' && playd_playlist_add "$fileName"; } \
					|| { echo "${1##*.}" | grep -q -i -E -e "^($PLAYD_PLAYLIST_FORMATS)$" && playd_import "$fileName"; } \
					|| playd_warn "\"$fileName\" doesn't seam to be valid file for playback. Ignoring" "to override use:" "  playd --nocheck $fileName"
			elif [ -d "$fileName" ]; then
				rm -f "$PLAYD_PLAYLIST.tmp"
				playd_mk_playlist "$fileName"
				[ $playd_append -eq 1 ] \
					&& cat "$PLAYD_PLAYLIST.tmp" >> "$PLAYD_PLAYLIST" \
					|| { cp -f "$PLAYD_PLAYLIST.tmp" "$PLAYD_PLAYLIST"; playd_append=1; }
				playd_put "loadlist '$PLAYD_PLAYLIST' $playd_append"
			else
				playd_warn "\"$fileName\" doesn't seam to be valid file for playback. Ignoring" 'to override use:' "  playd --nocheck $fileName"
			fi
		;;

	esac

	shift
done

exit 0
# vim: set ts=4 sw=4 foldminlines=3 fdm=marker:
