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
		if ! pacman $opt_confirm "${pacman_rootopt[@]}" -Su freebsd-world bash freebsd-init base base-devel "${opt_install[@]}"; then
			die "Failed to install build chroot"
		fi
	elif (( $opt_update )); then
		if ! pacman $opt_confirm "${pacman_rootopt[@]}" -Syu --needed "${opt_install[@]}"; then
			die "Failed to update build chroot"
		fi
	fi

	install -m644 "${pacman_conf_path}" "${builddir}/etc/pacman.conf"
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

        if check_mountfs fdescfs fdescfs ; then
                msg "mounting fdescfs"
                mount -t fdescfs fdescfs "${builddir}/dev/fs" || die "Failed to mount fdescfs"
        fi

}

inroot() {
	chroot "${builddir}" "$@"
}

configure_chroot() {
	sed -i '' -e '/^PACKAGER=/d' "$builddir/etc/makepkg.conf"
	echo 'PACKAGER="'"$PACKAGER"\" >> "$builddir/etc/makepkg.conf" \
		|| die "Failed to add PACKAGER information"

	install -dm755 "${builddir}/var/cache/pacman/pkg" || die "Failed to setup package cache mountpoint"
	mount_into_chroot

	msg "Running setup script %s" "$setup_script"
	install -m644 "$setup_script" "${builddir}/root/setup.sh"
	chroot "${builddir}" /usr/bin/bash /root/setup.sh

	msg "Initializing the keyring"
	chroot "${builddir}" pacman-key --init
	chroot "${builddir}" pacman-key --populate archbsd

	msg "Setting up networking"
	install -m644 /etc/resolv.conf "${builddir}/etc/resolv.conf"

	msg "Creating user 'builder'"
	chroot "${builddir}" pw userdel builder || true
	chroot "${builddir}" pw useradd -n builder -u 1001 -c builder -s /usr/bin/bash -m \
		|| die "Failed to create user 'builder'"

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
	chroot "${builddir}" /usr/bin/su -l builder -c "cd ~/package && bsdtar --strip-components=1 -xvf ${srcpkg}" || die "Failed to unpack sources"
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
	local synccmd=(--asroot --nobuild --syncdeps --noconfirm --noextract)
	chroot "${builddir}" /usr/bin/bash -c "cd /home/builder/package && makepkg ${synccmd[*]}" || die "Failed to sync package dependencies"
	[[ $opt_keepbuild == 1 ]] || chroot "${builddir}" /usr/bin/bash -c "cd /home/builder/package && rm -rf pkg src"        || die "Failed to clean package build directory"
	chroot "${builddir}" /usr/bin/bash -c "chown -R builder:builder /home/builder/package"    || die "Failed to reown package directory"
}

run_prepare() {
	if (( $opt_kill_ld )); then
		msg "Killing previous ld-hints"
		rm -f "${builddir}/var/run/ld"{,-elf,elf32,32}".so.hints"
	fi

	msg "Running prepare script %s" "$prepare_script"
	install -m644 "$prepare_script" "${builddir}/root/prepare.sh"
	chroot "${builddir}" /usr/bin/bash /root/prepare.sh

	msg "Running ldconfig service"
	chroot "${builddir}" /usr/sbin/service ldconfig onestart
}

start_build() {
	msg "Starting build"
	chroot "${builddir}" /usr/bin/su -l builder -c "cd ~/package && makepkg ${makepkgargs[*]}" || die "Failed to build package"
}

move_packages() {
	msg "Copying package archives"
	submsg "to $fulloutput"
	mkdir -p "$fulloutput"
	mv "${builddir}/home/builder/package/"*.pkg.tar.xz "$fulloutput" ||
		die "Failed to fetch packages..."
}
