#   Copyright (c) 2013 ArchBSD Team
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.

submsg() {
	local mesg=$1; shift
	printf "\033[1;35m  ->\033[0;0m ${mesg}\n" "$@"
}

preconf() {
	progname=${0##*/}

	msg() {
		local mesg=$1; shift
		printf "\033[1;34m==>\033[0;0m ${mesg}\n" "$@"
	}

	want_unmount=0
	die() {
		msg "$@"
		if (( $want_unmount )); then
			do_unmount
		fi
		exit 1
	}
}

checkconf() {
	if [[ ! -e "/etc/pacman.conf.clean" ]]; then
		die "/etc/pacman.conf.clean not found"
	fi
}

newmsg() {
	msg() {
		local mesg=$1; shift
		printf "\033[1;34m==>\033[0;0m [$repo/$package] ${mesg}\n" "$@"
	}
}

readconf() {
	source /etc/makepkg.conf
	if (( ! ${#PACKAGER} )); then
		die "Empty PACKAGER variable not allowed in /etc/makepkg.conf"
	fi
	# don't allow the commented out thing either: :P
	if [[ $PACKAGER == "John Doe <john@doe.com>" ]]; then
		die "Please update the PACKAGER variable in /etc/makepkg.conf"
	fi

	cachedir=/var/cache/pacman/pkg
	abstree=/var/absd-build/abs
	buildtop=/var/absd-build/build
	subvol=INVALID
	zfs_compression=gzip
	configfile="/etc/archbsd-build.conf"
	[ -f "$configfile" ] || die "please create a config in $configfile"
	source "$configfile"
	package_output=${package_output:-${buildtop}/output}
	builder_bashrc=${builder_bashrc:-${buildtop}/scripts/bashrc}
	setup_script=${setup_script:-${buildtop}/scripts/setup_root}
	prepare_script=${prepare_script:-${buildtop}/scripts/prepare_root}
	subvol_dir=${subvol_dir:-${buildtop}/subvol}

	if [[ $subvol == "INVALID" ]]; then
		zfs_enabled=0
	else
		zfs_enabled=1
	fi
}

postconf() {
	do_unmount() {
		[ -z ${builddir} || "x${builddir}" == ""] || return;
		msg "unmounting binds"
		umount "${builddir}"/{dev,var/cache/pacman/pkg} 2>/dev/null
		umount "${builddir}"/{proc,compat/linux/proc} 2>/dev/null
	}
	do_unmount
	want_unmount=0
}

load_config() {
	preconf
	checkconf
	readconf
	postconf
}

check_source() {
	#msg "Creating source package..."
	cd "$fullpath"
	#makepkg -Sf || die "failed creating src package"

	[ -f "$srcpkg" ] || die "Not a valid source package: %s" "$srcpkg"
}
