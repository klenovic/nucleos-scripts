#!/bin/sh
##############################################################################
#  Copyright (C) 2009  Ladislav Klenovic <klenovic@nucleonsoft.com>
#
#  This file is part of Nucleos kernel.
#
#  Build a cross compiler. Based on crosstool by Dan Kegel.
#  See http://www.kegel.com/crosstool for more details.
#
#  Nucleos kernel is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, version 2 of the License.
##############################################################################

###
# Build a cross toolchain.
# Only the binutils-gcc-newlib configuration is supported for now.
#
# E.g.:
# mkdir toolchain
# cd toolchain
# copy this script into toolchain
# run:
#   KERNELDIR=/path/to/nucleos/kernel ./buildcross.sh -b /path/to/binutils -c /path/to/gcc -n /path/to/newlib -g /path/to/gcc
#
# NOTE: The binutils, gcc and newlib must ported to nucleos.
###

cpu=i686
manufacturer=pc
kernel=nucleos
os=newlib

build=i686-pc-linux-gnu

workdir=`pwd`
prefix=$workdir/crosstool
target=${cpu}-${manufacturer}-${kernel}-${os}

# source directory
binutils_srcdir=
# build
binutils_build=$build
# target string
binutils_target=$target
# building directory
binutils_builddir=

# core for build the full cross compiler
gcc_core_srcdir=
gcc_core_build=$build
gcc_core_target=$target
gcc_core_builddir=
gcc_core_prefix=
gcc_core_prefix_link=$workdir/gcc-core

# core for build the full cross compiler
glibc_srcdir=
glibc_target=
glibc_build=$build
glibc_host=$target
glibc_builddir=

# full cross compiler
gcc_srcdir=
gcc_build=$build
gcc_target=$target
gcc_builddir=

# newlib
newlib_srcdir=
newlib_build=$build
newlib_target=$target
newlib_builddir=

usage()
{
	echo "Usage: `basename $0` [-h] [-b binutils] [-c core_gcc] [-g full_gcc] [-n newlib] [-p cross]"
	echo "[-b binutils package]: path to binutils directory"
	echo "[-c core gcc package]: path to gcc core directory"
	echo "[-g full gcc package]: path to gcc directory"
	echo "[-n newlib package]: path to newlib directory"
	echo "[-p core_cross:cross]: installation prefix for core cross and full cross toolset (current directory is default)"
	echo "                       DON'T USE THIS INTENDED FOR FUTURE!"
	echo "[-h]: this help"
}

# Parse the string which si in form first:second and print the
# required one according to second argument
#  arg1  string to parse
#  arg2  which string is required to return
parse_string()
{
	# what to return
	if [[ $2 == 1 ]]; then
		echo ${1%:*}
	fi

	if [[ $2 == 2 ]]; then
		# remove the first string
		_str2=${1#${1%:*}}
		# remove `:' from begining
		_str2=${_str2#:}
		echo $_str2
	fi

	echo ""
}

abspath()
{
	if [ -n $1 ]; then
		echo `cd $1;pwd`
	fi

	echo ""
}

install_system_headers()
{
	echo "Installing system headers ..."
	if [[ "$1" == "x" ]]; then
		echo "Missing kernel directory (set KERNELDIR)!"
		exit 1
	fi

	kernel_dir=${1#x}

	if [[ ! -e $kernel_dir ]]; then
		echo "Kernel directory doesn't exist!"
		exit 1
	fi

	kernel_dir=`abspath $kernel_dir`

	if [[ "$2" == "x" ]]; then
		echo "Missing destination path for system headers!"
		exit 1
	fi

	dst_headers_dir=${2#x}

	if [[ ! -e $dst_headers_dir ]]; then
		echo "Destination directory for headers doesn't exist!"
		exit 1
	fi

	dst_headers_dir=`abspath $dst_headers_dir`

	prevdir=`pwd`
	cd $kernel_dir
	# generate kernel headers
	make headers_check
	cd $prevdir

	mkdir -p $dst_headers_dir

	# FIXME: expects that headers were installed in kernel tree
	#        i.e. `make ARCH=$arch headers_install' was executed
	cp -r $kernel_dir/usr/include/* $dst_headers_dir/
}

# build install binutils
build_binutils()
{
	echo "Building binutils ($binutils_name) ..."
	if [ -a $binutils_builddir ]; then
		echo "Deleting $binutils_builddir ..."
		rm -rf $binutils_builddir
	fi

	mkdir -p $binutils_builddir

	if [[ $? != 0 ]]; then
		echo "Can't create build directory!"
		exit 1
	fi

	cd $binutils_builddir
	$binutils_srcdir/configure --build=$binutils_build \
				   --target=$binutils_target \
				   --prefix=$prefix \
				   --disable-nls \
				   --with-gnu-as \
				   --with-gnu-ld \
				   $binutils_sysroot_arg

	# build
	make all
	make install

	echo "Done"

	cd $workdir
}

# build core gcc (just to build newlib or glibc)
build_gcc_core()
{
	echo "Building core gcc ($gcc_core_name) ..."
	if [ -a $gcc_core_builddir ]; then
		echo "Deleting $gcc_core_builddir ..."
		rm -rf $gcc_core_builddir
	fi

	mkdir -p $gcc_core_builddir

	if [[ $? != 0 ]]; then
		echo "Can't create build directory!"
		exit 1
	fi

	cd $gcc_core_builddir

	# Use --with-local-prefix so older gccs don't look in /usr/local (http://gcc.gnu.org/PR10532)
	# Use funky prefix so it doesn't contaminate real prefix, in case gcc_srcdir != gcc_core_srcdir

	$gcc_core_srcdir/configure --build=$gcc_core_build \
				   --target=$gcc_core_target \
				   --prefix=$prefix \
				   --with-local-prefix=${prefix}/${target} \
				   --disable-multilib \
				   --without-headers \
				   --with-newlib \
				   --disable-nls \
				   --enable-threads=no \
				   --enable-symvers=gnu \
				   --enable-languages=c \
				   --disable-shared \
				   --with-gnu-as \
				   --with-gnu-ld \
				   ${gcc_core_sysroot_arg}

	# build
	make all-gcc
	make install-gcc

	echo "Done"

	cd $workdir
}

# build newlib
build_newlib()
{
	if [ -a $newlib_builddir ]; then
		echo "Deleting $newlib_builddir ..."
		rm -rf $newlib_builddir
	fi

	echo "Creating build directory ..."
	mkdir -p $newlib_builddir

	if [[ $? != 0 ]]; then
		echo "Can't create build directory!"
		exit 1
	fi

	echo "Configure $newlib_name package ..."
	cd $newlib_builddir

	CC_FOR_TARGET=$prefix/bin/$gcc_core_target-gcc \
	AS_FOR_TARGET=$prefix/bin/$binutils_target-as \
	LD_FOR_TARGET=$prefix/bin/$binutils_target-ld \
	AR_FOR_TARGET=$prefix/bin/$binutils_target-ar \
	RANLIB_FOR_TARGET=$prefix/bin/$binutils_target-ranlib \
	$newlib_srcdir/configure --build=$newlib_build \
				 --target=$newlib_target \
				 --prefix=$prefix \
				 --with-gnu-as \
				 --with-gnu-ld \
				 --disable-shared

	# build
	echo "Building $newlib_name ..."
	make
	make install

	echo "Done"

	cd $workdir
}

# build full gcc
build_gcc_full()
{
	if [ -a $gcc_builddir ]; then
		echo "Deleting $gcc_builddir ..."
		rm -rf $gcc_builddir
	fi

	echo "Creating build directory ..."
	mkdir -p $gcc_builddir

	if [[ $? != 0 ]]; then
		echo "Can't create build directory!"
		exit 1
	fi

#
# without libstdc++ support
#
#	echo "Run autoconf in $gcc_srcdir/libstdc++-v3"
#	cd $gcc_srcdir/libstdc++-v3 >&/dev/null
#	autoconf
#	cd $workdir

	echo "Configure $gcc_name package ..."
	cd $gcc_builddir

	CC_FOR_TARGET=$prefix/bin/$gcc_core_target-gcc \
	AS_FOR_TARGET=$prefix/bin/$binutils_target-as \
	LD_FOR_TARGET=$prefix/bin/$binutils_target-ld \
	AR_FOR_TARGET=$prefix/bin/$binutils_target-ar \
	RANLIB_FOR_TARGET=$prefix/bin/$binutils_target-ranlib \
	$gcc_srcdir/configure --build=$gcc_build \
			      --target=$gcc_target \
			      --prefix=$prefix \
			      --enable-languages=c \
			      --with-headers=$prefix/$target/include \
			      --disable-shared \
			      --disable-nls \
			      --enable-symvers=gnu \
			      --enable-c99 \
			      --enable-long-long \
			      --with-gnu-as \
			      --with-gnu-ld \
			      --with-newlib \
			      $gcc_sysroot_arg

	# build
	echo "Building gcc ..."
	make all
	make install

	echo "Done"

	cd $workdir
}

# Check arguments.
while getopts "b:c:g:l:n:hp:" OPT "$@"
do
	case "$OPT" in
	b) # binutils package
		binutils_srcdir=`parse_string $OPTARG 1`

		if [ -z  $binutils_srcdir ]; then
			echo "Empty argument (missing binutils source)!"
			exit 1
		fi

		binutils_srcdir=`abspath $binutils_srcdir`
		# just base name
		binutils_name=`basename $binutils_srcdir`

		# build dircetory path
		binutils_builddir=$workdir/${binutils_name}-build
		;;

	c) # gcc cores
		gcc_core_srcdir=`parse_string $OPTARG 1`

		if [ -z  $gcc_core_srcdir ]; then
			echo "Empty argument (missing gcc core source)!"
			exit 1
		fi

		gcc_core_srcdir=`abspath $gcc_core_srcdir`
		gcc_core_name=`basename $gcc_core_srcdir`

		# build dircetory path
		gcc_core_builddir=$workdir/${gcc_core_name}-core-build
		# installation directory
		gcc_core_prefix=$workdir/${gcc_core_name}-core-install
		;;

	g) # gcc
		gcc_srcdir=`parse_string $OPTARG 1`

		if [ -z  $gcc_srcdir ]; then
			echo "Empty argument (missing gcc source)!"
			exit 1
		fi

		gcc_srcdir=`abspath $gcc_srcdir`
		gcc_name=`basename $gcc_srcdir`

		# build dircetory path
		gcc_builddir=$workdir/${gcc_name}-build
		;;

	n) # newlib
		newlib_srcdir=`parse_string $OPTARG 1`

		if [ -z  $newlib_srcdir ]; then
			echo "Empty argument (missing newlib source)!"
			exit 1
		fi

		newlib_srcdir=`abspath $newlib_srcdir`
		newlib_name=`basename $newlib_srcdir`

		# build dircetory path
		newlib_builddir=$workdir/${newlib_name}-build
		;;

	h) # usage
		usage
		exit 0
		;;

	p) # prefixes
		prefix=$OPTARG
		parse_string $OPTARG 1
		parse_string $OPTARG 2

		if [ -z "${prefix}" ]; then
			# default install path for toolset
			prefix=$workdir/crosstool
		else
			if [[ $prefix != /* ]]; then
				prefix=$workdir/$prefix
			fi
		fi
		;;

	*) # unknown option
		echo $OPTARG
		usage
		exit 1
		;;

	esac
done

echo "Creating installation directory ..."

mkdir -p ${prefix}/${target}

### Build binutils
if [ -n "$binutils_builddir" ]; then
	build_binutils
fi

### Build a core gcc
if [ -n "$gcc_core_builddir" ]; then
	build_gcc_core
fi

### Build a newlib
if [ -n "$newlib_builddir" ]; then
	build_newlib
fi

echo "Install system headers"
header_dir=$prefix/$target/include
install_system_headers x${KERNELDIR} x${header_dir}

### Build full cross compiler
if [ -n "$gcc_builddir" ]; then
	build_gcc_full
fi

echo "Cross-toolchain build complete"

exit 0
