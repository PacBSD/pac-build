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

# The following function is taken from 'makepkg', part of pacman, to ensure
# compatibility. Hence the GPLv2 license... :|
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
