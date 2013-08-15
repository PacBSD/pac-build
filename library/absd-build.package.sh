get_full_version() {
	if [[ -z $1 ]]; then
		if [[ $epoch ]] && (( ! $epoch )); then
			printf "%s\n" "$pkgver-$pkgrel"
		else
			printf "%s\n" "$epoch:$pkgver-$pkgrel"
		fi
	else
		for i in pkgver pkgrel epoch; do
			local indirect="${i}_override"
			eval $(declare -f package_$1 | gsed -n "s/\(^[[:space:]]*$i=\)/${i}_override=/p")
			[[ -z ${!indirect} ]] && eval ${indirect}=\"${!i}\"
		done
		if (( ! $epoch_override )); then
			printf "%s\n" "$pkgver_override-$pkgrel_override"
		else
			printf "%s\n" "$epoch_override:$pkgver_override-$pkgrel_override"
		fi
	fi
}

getsource() {
	cd "${fullpath}"
	source PKGBUILD
	pkgbase=${pkgbase:-${pkgname[0]}}
	epoch=${epoch:-0}
	fullver=$(get_full_version)
	echo "${pkgbase}-${fullver}${SRCEXT}"
}
