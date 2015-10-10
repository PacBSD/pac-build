#   Copyright (c) 2013 PacBSD Team
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

clean_previous() {
	do_unmount 2>/dev/null
	msg "Cleaning previous work..."
	find "$builddir" -print0 | xargs -0 chflags noschg
	rm -rf "$builddir"
}

create_chroot() {
	msg "Installing chroot environment..."
	submsg 'using: %s' "${pacman_conf_path}"
	mkdir -p "$builddir" || die "Failed to create build dir: %s" "$builddir"
	mkdir -p "$builddir/var/lib/pacman"

	pacman_rootopt=(--config "${pacman_conf_path}" --root "$builddir" --cachedir "$cachedir")

	if (( ! $opt_nosync )); then
		if ! pacman $opt_confirm "${pacman_rootopt[@]}" -Sy; then
			die "Failed to sync databases"
		fi
	fi

	if (( ! $opt_existing )); then
		if ! pacman $opt_confirm "${pacman_rootopt[@]}" -Su freebsd-world bash freebsd-init gnu-coreutils base base-devel "${opt_install[@]}"; then
			die "Failed to install build chroot"
		fi
	elif (( $opt_update )); then
		if ! pacman $opt_confirm "${pacman_rootopt[@]}" -Syu --needed "${opt_install[@]}"; then
			die "Failed to update build chroot"
		fi
	fi

	install -m644 "${pacman_conf_path}" "${builddir}/etc/pacman.conf"
	if [ -d ${builddir} ]; then 
		rmlink "${builddir}/etc/localtime"
	fi

	if [ -n "${timezone}" ] && ! -L ${builddir}/etc/localtime ] || [ ! -f ${builddir}/etc/localtime ]; then
		ln -s "/usr/share/zoneinfo/${timezone}" ${builddir}/etc/localtime
	fi
}

check_mountfs() {
	for i in "${opt_mountfs[@]}"; do
		for j in "$@"; do
			if [[ "$i" == "$j" ]]; then
				return 0
			fi
		done
	done
	return 1
}

mount_into_chroot() {
	want_unmount=1
	mount_nullfs {,"${builddir}"}/var/cache/pacman/pkg || die "Failed to bind package cache"
	mount -t devfs devfs "${builddir}/dev" || die "Failed to mount devfs"
	mount -t fdescfs fdescfs "${builddir}/dev/fd" || die "Failed to mount fdescfs"

	if check_mountfs proc procfs; then
		msg "mounting procfs"
		install -dm755 "${builddir}/proc"
		mount -t procfs procfs "${builddir}/proc" || die "Failed to mount procfs"
	fi
	if check_mountfs linproc linprocfs ; then
		msg "mounting linprocfs"
		install -dm755 "${builddir}/compat/linux/proc"
		mount -t linprocfs linprocfs "${builddir}/compat/linux/proc" || die "Failed to mount linprocfs"
	fi
}

inroot() {
	if (( $opt_jail )); then
		jail -c path=${builddir} ${jail_args[@]} command="$@"
	else
		chroot "${builddir}" "$@"
	fi
}

configure_chroot() {
	sed -i '' -e '/^PACKAGER=/d' "$builddir/etc/makepkg.conf"
	echo 'PACKAGER="'"$PACKAGER"\" >> "$builddir/etc/makepkg.conf" \
		|| die "Failed to add PACKAGER information"

	install -dm755 "${builddir}/var/cache/pacman/pkg" || die "Failed to setup package cache mountpoint"
	mount_into_chroot

	msg "Running setup script %s" "$setup_script"
	install -m644 "$setup_script" "${builddir}/root/setup.sh"
	if (( $opt_jail )); then
		jail -c path=${builddir} ${jail_args[@]} command=/usr/bin/bash /root/setup.sh
	else
		chroot "${builddir}" /usr/bin/bash /root/setup.sh
	fi

	msg "Initializing the keyring"
	if (( $opt_jail )); then
		 jail -c path=${builddir} ${jail_args[@]} command=pacman-key --init
		 jail -c path=${builddir} ${jail_args[@]} command=pacman-key --populate pacbsd
	else
		chroot "${builddir}" pacman-key --init
		chroot "${builddir}" pacman-key --populate pacbsd
	fi

	msg "Setting up networking"
	install -m644 /etc/resolv.conf "${builddir}/etc/resolv.conf"

	msg "Creating user 'builder'"
	if (( $opt_jail )); then
		jail -c path=${builddir} ${jail_args[@]} command=pw userdel builder || true
		jail -c path=${builddir} ${jail_args[@]} command=pw useradd -n builder -u 1001 -c builder -s /usr/bin/bash -m \
			|| die "Failed to create user 'builder'"
	else
		chroot "${builddir}" pw userdel builder || true
		chroot "${builddir}" pw useradd -n builder -u 1001 -c builder -s /usr/bin/bash -m \
			|| die "Failed to create user 'builder'"
	fi
	msg "Installing shell profile..."
	install -o 1001 -m644 "$builder_bashrc" "${builddir}/home/builder/.bashrc"

	msg "Linking .profile to .bashrc"
	ln -sf .bashrc "${builddir}/home/builder/.profile"
}

create_builder_home() {
	msg "Installing package building directory"
	install -o 1001 -dm755 "${builddir}/home/builder/package"
	install -o 1001 -m644 "$fullpath/$srcpkg" "${builddir}/home/builder/package"

	msg "Unpacking package sources"
	if (( $opt_jail )); then
		jail -c path=${builddir} ${jail_args[@]} command=/usr/bin/su -l builder -c "cd ~/package && bsdtar --strip-components=1 -xvf ${srcpkg}" || die "Failed to unpack sources"
	else
		chroot "${builddir}" /usr/bin/su -l builder -c "cd ~/package && bsdtar --strip-components=1 -xvf ${srcpkg}" || die "Failed to unpack sources"
	fi
	source "$fullpath/PKGBUILD"
	for i in "${source[@]}"; do
		case "$i" in
			*::*) i=${i%::*} ;;
			*)    i=${i##*/} ;;
		esac
		if [ -e "$fullpath/$i" ]; then
			msg "Copying file %s" "$i"
			#install -o 1001 -m644 "$fullpath/$i" "${builddir}/home/builder/package/$i"
			cp -a "$fullpath/$i" "${builddir}/home/builder/package/$i"
			chown -R 1001 "${builddir}/home/builder/package/$i"
		else
			msg "You don't have this file? %s" "$i"
		fi
	done
}

syncdeps() {
	msg "Syncing dependencies"
	local synccmd=(--nobuild --syncdeps --noconfirm --noextract)
	if (( $opt_jail )); then
		 jail -c path=${builddir} ${jail_args[@]} command=/usr/bin/bash -c "cd /home/builder/package && makepkg ${synccmd[*]}" || die "Failed to sync package dependencies"
	else
		chroot "${builddir}" /usr/bin/bash -c "cd /home/builder/package && makepkg ${synccmd[*]}" || die "Failed to sync package dependencies"
	fi

	if (( $opt_jail )); then
		[[ $opt_keepbuild == 1 ]] || jail -c path=${builddir} ${jail_args[@]} command=/usr/bin/bash -c "cd /home/builder/package && rm -rf pkg src" || die "Failed to clean package build directory"
	else
		[[ $opt_keepbuild == 1 ]] || chroot "${builddir}" /usr/bin/bash -c "cd /home/builder/package && rm -rf pkg src"        || die "Failed to clean package build directory"
	fi
	if (( $opt_jail )); then
		jail -c path=${builddir} ${jail_args[@]} command=/usr/bin/bash -c "chown -R builder:builder /home/builder/package" || die "Failed to reown package directory"
	else
		chroot "${builddir}" /usr/bin/bash -c "chown -R builder:builder /home/builder/package"    || die "Failed to reown package directory"
	fi
}

run_prepare() {
	if (( $opt_kill_ld )); then
		msg "Killing previous ld-hints"
		rm -f "${builddir}/var/run/ld"{,-elf,elf32,32}".so.hints"
	fi

	msg "Running prepare script %s" "$prepare_script"
	install -m644 "$prepare_script" "${builddir}/root/prepare.sh"
	if (( $opt_jail )); then
		jail -c path=${builddir} ${jail_args[@]} command=/usr/bin/bash /root/prepare.sh
	else
		chroot "${builddir}" /usr/bin/bash /root/prepare.sh
	fi

	msg "Running ldconfig service"
	if (( $opt_jail )); then
		jail -c path=${builddir} ${jail_args[@]} command=/usr/sbin/service ldconfig onestart
	else
		chroot "${builddir}" /usr/sbin/service ldconfig onestart
	fi
}

start_build() {
	msg "Starting build"
	if (( $opt_jail )); then
		 jail -c path=${builddir} ${jail_args[@]} command=/usr/bin/su -l builder -c "cd ~/package && makepkg ${makepkgargs[*]}" || die "Failed to build package"
	else
		chroot "${builddir}" /usr/bin/su -l builder -c "cd ~/package && makepkg ${makepkgargs[*]}" || die "Failed to build package"
	fi
}

move_packages() {
	msg "Copying package archives"
	submsg "to $fulloutput"
	mkdir -p "$fulloutput"
	mv "${builddir}/home/builder/package/"*.pkg.tar.xz "$fulloutput" ||
		die "Failed to fetch packages..."
}
