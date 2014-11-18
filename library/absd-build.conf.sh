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

newmsg() {
	msg() {
		local mesg=$1; shift
		printf "\033[1;34m==>\033[0;0m [$repo/$package_name] ${mesg}\n" "$@"
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
	vardir=/var/absd
	default_profile=x86_64
	subvol_x86_64=INVALID
	subvol_i686=INVALID
	subvol_arm=INVALID
	subvol=INVALID
	zfs_compression=gzip
	configfile="/etc/archbsd-build.conf"
	[ -f "$configfile" ] || die "please create a config in $configfile"
	source "$configfile"
}

postconf() {
	default_profile=${default_profile:-x86_64}
	build_profile=${build_profile:-${default_profile}}
	package_output=${package_output:-${buildtop}/output}
	builder_bashrc=${builder_bashrc:-${vardir}/scripts/bashrc}
	setup_script=${setup_script:-${vardir}/scripts/setup_root}
	prepare_script=${prepare_script:-${vardir}/scripts/prepare_root}
	subvol_dir=${subvol_dir:-${buildtop}/subvol/${build_profile}}

	eval "subvol=\${subvol_${build_profile}:-INVALID}"
	eval "pacman_conf_path=\${pacman_conf_${build_profile}:-/etc/pacman.conf.clean}"
	# eval "makepkg_conf_path=\${makepkg_conf_${build_profile}:-/etc/makepkg.conf}"

	if [[ ! -e "${pacman_conf_path}" ]]; then
		die "${pacman_conf_path} not found"
	fi

	if [[ $subvol == "INVALID" ]]; then
		zfs_enabled=0
	else
		zfs_enabled=1
	fi
	do_unmount() {
		if [[ "${builddir}" == "" ]]; then
			return;
		fi
		msg "unmounting binds"
		umount "${builddir}"/{dev,var/cache/pacman/pkg} 2>/dev/null
		umount "${builddir}"/{proc,compat/linux/proc} 2>/dev/null
		if (( $opt_zfs )); then
			zfs_unmount_chroot
		fi
	}
	do_unmount
	want_unmount=0
}

load_config() {
	preconf
	readconf
}

check_source() {
	#msg "Creating source package..."
	cd "$fullpath"
	#makepkg -Sf || die "failed creating src package"

	[ -f "$srcpkg" ] || die "Not a valid source package: %s" "$srcpkg"
}
