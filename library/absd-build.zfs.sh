zfs_check() {
	if (( ! $zfs_enabled )); then
		die "ZFS not configured"
	fi
}

zvol_exists() {
	zfs list -t all | grep -q "^$1 "
}

zfs_exists() {
	if (zvol_exists "$subvol"); then
		if (( ! $1 )); then
			die "Subvolume \`${subvol}' already exists."
		fi
	else
		if (( $1 )); then
			die "Subvolume \`${subvol}' does not exists."
		fi
	fi
}

zvol_ismounted() {
	mount | grep -q "^$1 on"
}

zfs_ismounted() {
	zvol_ismounted "$subvol"
}

zfs_mounted() {
	if zfs_ismounted; then
		if (( ! $1 )); then
			die "Subvolume \`${subvol}' is currently mounted."
		fi
	else
		if (( $1 )); then
			die "Subvolume \`${subvol}' is currently not mounted."
		fi
	fi
}

zfs_domount() {
	msg "mounting subvolume \`${subvol} at: ${subvol_dir}"
	mount -t zfs "$subvol" "$subvol_dir" \
	|| die "Failed to mount subvolume"
}

zfs_mount() {
	if zfs_ismounted; then
		msg "using already-mounted subvolume \`${subvol}'"
	else
		zfs_domount
	fi
}

zfs_unmount() {
	builddir="${subvol_dir}"
	do_unmount
	if zfs_ismounted; then
		umount "${subvol_dir}"
	fi
}

zfs_init() {
	zfs_exists 0

	msg "preparing directories for subvolume \`${subvol}'"
	if [ ! -d "${subvol_dir}" ]; then
		mkdir "${subvol_dir}" \
		|| die "Failed to create subvolume mountpoint at $subvol_dir"
	fi

	msg "creating subvolume \`${subvol}'"
	zfs create -o mountpoint=legacy -o "compression=$zfs_compression" "$subvol" \
	|| die "Failed to create subvolume"

	msg "mounting new subvolume"
	zfs_domount

	msg "installing base system"
	submsg "target:   $subvol_dir"
	submsg "cachedir: $cachedir"
	builddir="$subvol_dir"
	opt_nosync=0
	opt_existing=0
	opt_update=0
	opt_confirm=--noconfirm
	opt_install=()
	create_chroot
	opt_kill_ld=0
	configure_chroot
	zfs_unmount
}

zfs_update() {
	zfs_exists 1
	zfs_mount

	msg "updating subvolume \`${subvol}'"
	builddir="$subvol_dir"
	opt_nosync=0
	opt_existing=1
	opt_update=1
	opt_confirm=--noconfirm
	opt_install=()
	create_chroot
	opt_kill_ld=0
	configure_chroot
	zfs_unmount
}

zfs_remove() {
	zfs_exists 1
	builddir="$subvol_dir"
	zfs_unmount
	zfs_mounted 0
	msg "destroying subvolume \`${subvol}'"
	zfs destroy "$subvol"
}

run_zfsopts() {
	case "$1" in
		init)   zfs_check ; zfs_init   ;;
		update) zfs_check ; zfs_update ;;
		remove) zfs_check ; zfs_remove ;;
		*)      return ;;
	esac
	exit 0
}

zfs_configure() {
	snapshot="${subvol}@${repo}.${package}"
	repovol="${subvol}__${repo}.${package}"
}

zfs_remove_dataset() {
	if zvol_exists "$1"; then
		if zvol_ismounted "$1"; then
			umount "$1" || die "unmounting failed"
		fi
		zvol_ismounted "$1" && die "still mounted: $1"

		msg "removing zfs dataset $1"
		zfs destroy "$1"
	fi
}

zfs_clean_previous() {
	do_unmount
	zfs_remove_dataset "$repovol"
	zfs_remove_dataset "$snapshot"
	rm -rf "$builddir"
}

zfs_create_chroot() {
	if zvol_exists "$repovol"; then
		msg "using existing snapshot"
		if ! mount | grep -q "^$repovol on $builddir"; then
			mount -t zfs "$repovol" "$builddir" \
			|| die "Failed to mount existing clone"
		fi
		return
	fi

	msg "creating snapshot..."
	zfs snapshot "$snapshot" \
	|| die "failed to create snapshot"

	msg "creating writable clone..."
	zfs clone -o mountpoint=legacy              \
	          -o "compression=$zfs_compression" \
	          "$snapshot" "$repovol"            \
	|| die "failed to create writable clone"

	msg "setting up mountpoint"
	mkdir -p "$builddir" || die "Failed to create mountpoint dir: %s" "$builddir"

	msg "mounting clone"
	mount -t zfs "$repovol" "$builddir" \
	|| die "Failed to mount clone"
}

zfs_unmount_chroot() {
	umount "$builddir" || die "Failed to unmount clone from build directory"
}
