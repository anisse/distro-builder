#!/bin/bash
# Build EFLs on multiple distros


set -eo pipefail
set -x

REPOS="git://git.enlightenment.org/core/efl.git git://git.enlightenment.org/apps/terminology.git"

fedora_VERSIONS="24 25"
debian_VERSIONS="stretch"
ubuntu_VERSIONS="xenial yakkety"

CPUS=$(grep processor /proc/cpuinfo |wc -l)

ROOT=$PWD/distros

fedora_chroot() {
	local ver=$1
	local dir=$2
	shift 2
	local deps=$@

	dnf --assumeyes --quiet --releasever=$ver --installroot=$dir install systemd dnf fedora-release $deps
}

_core_debootstrap() {
	local mirror=$1
	local ver=$2
	local dir=$3

	# we could have debootstrap install everything, but it's quite slow, so we use apt instead
	debootstrap $ver $dir $mirror ||true #TODO: remove true here
}

_core_aptinstall() {
	local dir=$2
	shift 2
	local deps=$@

	systemd-nspawn -D $dir /bin/bash -c "apt-get update --quiet &&
		apt-get install --assume-yes --quiet --no-install-recommends $deps"
}

debian_chroot() {
	_core_debootstrap http://httpredir.debian.org/debian $@
	_core_aptinstall $@
}

ubuntu_chroot() {
	local dir=$2
	_core_debootstrap http://fr.archive.ubuntu.com/ubuntu/ $@
	rm -f $dir/etc/resolv.conf # let systemd-nspawn handle this
	# we need universe in ubuntu
	sed -ie 's/ main$/ main universe/g' $dir/etc/apt/sources.list
	_core_aptinstall $@
}

build_into() {
	local dir=$1
	shift
	local repos=$@

	systemd-nspawn -D $dir /bin/bash -c "
		set -eo pipefail
		set -x
		cd
		for r in $repos; do
			git clone \$r
			(
				cd \$(basename \$r .git)
				./autogen.sh --prefix=/usr
				make -j$CPUS
				make check
				make install
			)
		done
	"
}

build_distros() {
	for d in $@ ; do
		case $d in
			fedora)
				# Test for dnf
				;;
			debian|ubuntu)
				# Test for debootstrap
				;;
			*)
				echo Unknown distro $d
				exit 1
				;;
		esac
		# Maybe we should use associative arrays here
		declare _VERSIONS="${d}_VERSIONS"
		local VERSIONS="${!_VERSIONS}"
		local BUILD_CHROOT="${d}_chroot"
		local BUILD_CHROOT_DIR_PREFIX=$ROOT/${d}-
		for v in $VERSIONS ; do
			local dir=${BUILD_CHROOT_DIR_PREFIX}${v}
			BUILD_CHROOT_DEPS="$(cat ${d}-${v} 2>/dev/null || cat $d)"
			$BUILD_CHROOT $v $dir $BUILD_CHROOT_DEPS
			build_into $dir $REPOS
		done
	done
}

mkdir -p $ROOT

DISTROS="${@:-debian fedora}"
build_distros $DISTROS

