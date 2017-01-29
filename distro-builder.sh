#!/bin/bash
# Build EFLs on multiple distros


set -eo pipefail
set -x

REPOS="git://git.enlightenment.org/core/efl.git git://git.enlightenment.org/apps/terminology.git"

fedora_VERSIONS="24 25"
fedora_DEPS="bullet-devel libpng-devel libjpeg-turbo-devel gstreamer1-devel  gstreamer1-plugins-base-devel  zlib-devel luajit-devel libtiff-devel openssl-devel libcurl-devel dbus-devel glibc-devel fontconfig-devel freetype-devel fribidi-devel pulseaudio-libs-devel libsndfile-devel libX11-devel libXau-devel libXcomposite-devel libXdamage-devel libXdmcp-devel libXext-devel libXfixes-devel libXinerama-devel libXrandr-devel libXrender-devel libXScrnSaver-devel libXtst-devel libXcursor-devel libXp-devel libXi-devel mesa-libGL-devel giflib-devel libmount-devel libblkid-devel systemd-devel  poppler-cpp-devel poppler-devel LibRaw-devel libspectre-devel librsvg2-devel autoconf automake gcc gcc-c++ gettext-devel findutils tar xz libtool make"

debian_VERSIONS="stretch"
# TODO: this is not mine, fix
debian_DEPS="autopoint build-essential ccache check doxygen faenza-icon-theme git imagemagick libasound2-dev libblkid-dev libbluetooth-dev libbullet-dev libcogl-dev libfontconfig1-dev libfreetype6-dev libfribidi-dev libgif-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libharfbuzz-dev libibus-1.0-dev libiconv-hook-dev libjpeg-dev libblkid-dev libluajit-5.1-dev liblz4-dev libmount-dev libturbojpeg0-dev libpam0g-dev libpoppler-cpp-dev libpoppler-dev libpoppler-private-dev libproxy-dev libpulse-dev libraw-dev librsvg2-dev libscim-dev libsndfile1-dev libspectre-dev libssl-dev libsystemd-dev libtiff5-dev libtool libudisks2-dev libunibreak-dev libvlc-dev libwebp-dev libxcb-keysyms1-dev libxcursor-dev libxine2-dev libxinerama-dev libxkbfile-dev libxrandr-dev libxss-dev libxtst-dev"

ubuntu_VERSIONS="xenial yakkety"
ubuntu_DEPS="$debian_DEPS linux-tools-common"

CPU=$(grep processor /proc/cpuinfo |wc -l)

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

	systemd-nspawn -D $dir /bin/bash -c "apt-get update && apt-get install -y --no-install-recommends $deps"
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
				make -j$CPU
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
		declare _BUILD_CHROOT_PARAMS="${d}_DEPS"
		local VERSIONS="${!_VERSIONS}"
		local BUILD_CHROOT="${d}_chroot"
		local BUILD_CHROOT_PARAMS="${!_BUILD_CHROOT_PARAMS}"
		local BUILD_CHROOT_DIR_PREFIX=$ROOT/${d}-
		for v in $VERSIONS ; do
			local dir=${BUILD_CHROOT_DIR_PREFIX}${v}
			$BUILD_CHROOT $v $dir $BUILD_CHROOT_PARAMS
			build_into $dir $REPOS
		done
	done
}

mkdir -p $ROOT

DISTROS="${@:-debian fedora}"
build_distros $DISTROS

