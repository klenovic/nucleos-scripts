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

cpu=i686
manufacturer=pc
kernel=nucleos
os=newlib

workdir=`pwd`
prefix=$workdir/crosstool
target=${cpu}-${manufacturer}-${kernel}-${os}

# source directory
binutils_srcdir=
# patch
binutils_patch=
# target string
binutils_target=$target
# building directory
binutils_builddir=

# core for build the full cross compiler
gcc_core_srcdir=
gcc_core_patch=
gcc_core_target=$target
gcc_core_builddir=
gcc_core_prefix=
gcc_core_prefix_link=$workdir/gcc-core

# core for build the full cross compiler
glibc_srcdir=
glibc_patch=
glibc_target=
glibc_host=$target
glibc_builddir=

# full cross compiler
gcc_srcdir=
gcc_patch=
gcc_target=$target
gcc_builddir=

# newlib
newlib_srcdir=
newlib_patch=
newlib_target=$target
newlib_builddir=

usage()
{
	echo "Usage: `basename $0` [-h] [-b binutils[:patch]] [-c core_gcc[:patch]] [-g full_gcc[:patch]] [-n newlib[:patch]] [-p cross]"
	echo "[-b binutils package:patch]: path to binutils directory and patch if any"
	echo "[-c core gcc package:patch]: path to gcc core directory and patch if any"
	echo "[-g full gcc package:patch]: path to gcc directory and patch if any"
	echo "[-l glibc:patch]: path to glibc directory and patch if any"
	echo "[-n newlib package:patch]: path to newlib directory and patch if any"
	echo "[-p core_cross:cross]: installation prefix for core cross and full cross toolset (current directory is default)"
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

	mkdir -p $dst_headers_dir

	# FIXME: expects that headers were installed in kernel tree
	#        i.e. `make ARCH=$arch headers_install' was executed
	cp -r $kernel_dir/usr/include/asm $dst_headers_dir/
	cp -r $kernel_dir/usr/include/asm-generic $dst_headers_dir/
	cp -r $kernel_dir/usr/include/nucleos $dst_headers_dir/
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

	# whether to patch
	if [[ $binutils_patch ]]; then
		echo "Patch binutils ..."
		patch -d $binutils_srcdir -p1 < $binutils_patch

		if [[ $? != 0 ]]; then
			echo "Can't apply patches!"
			exit 1
		fi
	fi

	cd $binutils_builddir
	$binutils_srcdir/configure --target=$binutils_target --prefix=$prefix --disable-nls $binutils_sysroot_arg

	# build it
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

	# patch gcc if neccessary
	if [[ $gcc_core_patch ]]; then
		echo "Patch $gcc_core_name ..."
		patch -d $gcc_core_srcdir -p1 < $gcc_core_patch

		if [[ $? != 0 ]]; then
			echo "Can't apply patches!"
			exit 1
		fi
	fi

	# Copy headers to install area of bootstrap gcc, so it can build libgcc2
	mkdir -p $gcc_core_prefix/$target/include
	cp -r $header_dir/* $gcc_core_prefix/$target/include

	cd $gcc_core_builddir

	# Use --with-local-prefix so older gccs don't look in /usr/local (http://gcc.gnu.org/PR10532)
	# Use funky prefix so it doesn't contaminate real prefix, in case gcc_srcdir != gcc_core_srcdir

	$gcc_core_srcdir/configure --target=$gcc_core_target --prefix=$gcc_core_prefix \
				   --with-local-prefix=${sysroot} \
				   --disable-multilib \
				   --with-newlib \
				   ${gcc_core_sysroot_arg} \
				   --disable-nls \
				   --enable-threads=no \
				   --enable-symvers=gnu \
				   --enable-__cxa_atexit \
				   --enable-languages=c \
				   --disable-shared

	# build the core c
	make all-gcc
	make install-gcc

	echo "Done"

	cd $workdir

	ln -s $gcc_core_prefix $gcc_core_prefix_link
}


# build glibc (headers only)
build_glibc_headers()
{
	if [ -z ${KERNELDIR} ]; then
		echo "Missing kernel directory (set KERNELDIR)!"
		exit 1
	fi

	if [ -a $glibc_headers_build ]; then
		echo "Deleting $glibc_headers_build ..."
		rm -rf $glibc_headers_build
	fi

	echo "Creating build directory for glibc headers ..."
	mkdir -p $glibc_headers_build

	if [[ $? != 0 ]]; then
		echo "Can't create build directory for glibc headers!"
		exit 1
	fi

	cd ${glibc_headers_build}
	CC="gcc -O2" $glibc_srcdir/configure --prefix= \
					  --host=$glibc_host \
					  --with-headers=${KERNELDIR}/usr/include \
					  --disable-profile \
					  --disable-debug \
					  --without-gd  \
					  --disable-sanity-checks \
					  --without-__thread \
					  --disable-shared

	echo "Extract glibc headers ..."
	make cross-compiling=yes install_root=$workdir/${glibc_name}-headers install-headers

	echo "Done"

	cd $workdir
}

# build glibc
build_glibc()
{
	echo "Building glibc ($glibc_name) ..."
	if [ -a $glibc_builddir ]; then
		echo "Deleting $glibc_builddir ..."
		rm -rf $glibc_builddir
	fi

	mkdir -p $glibc_builddir

	if [[ $? != 0 ]]; then
		echo "Can't create build directory!"
		exit 1
	fi

	# patch has to be common for core and full
	if [[ $glibc_patch ]]; then
		echo "Patch $glibc_name ..."
		patch -d $glibc_srcdir -p1 < $glibc_patch

		if [[ $? != 0 ]]; then
			echo "Can't apply patches!"
			exit 1
		fi
	fi

	# rebuild `configure' from configure.in
	echo "--- run autoconf in $glibc_srcdir/sysdeps/unix/sysv/nucleos"
	cd $glibc_srcdir/sysdeps/unix/sysv/nucleos
	autoconf
	cd $glibc_builddir

	BUILD_CC=gcc CFLAGS="$TARGET_CFLAGS $EXTRA_TARGET_CFLAGS" CC="${target}-gcc $GLIBC_EXTRA_CC_ARGS" \
	AR=${target}-ar RANLIB=${target}-ranlib \
	$glibc_srcdir/configure --prefix=/usr --build=$($glibc_srcdir/scripts/config.guess) --host=$target \
				${GLIBC_EXTRA_CONFIG} ${DEFAULT_GLIBC_EXTRA_CONFIG} \
				--with-headers=$header_dir \
				--with-elf \
				--without-cvs \
				--disable-profile \
				--disable-debug \
				--without-gd \
				--disable-shared \
				--without-tls \
				--without-__thread \
				libc_cv_forced_unwind=yes libc_cv_c_cleanup=yes

	make cross-compiling=yes LD=${target}-ld RANLIB=${target}-ranlib lib
	make install_root=${sysroot} $glibc_sysroot_arg install

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

	if [[ $newlib_patch ]]; then
		echo "Patch $newlib_name ..."
		patch -d $newlib_srcdir -p1 < $newlib_patch

		if [[ $? != 0 ]]; then
			echo "Can't apply patches!"
			exit 1
		fi
	fi

	echo "Configure $newlib_name package ..."
	cd $newlib_builddir
	$newlib_srcdir/configure --target=$newlib_target --prefix=$prefix

	# build it
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

	if [[ $gcc_patch ]]; then
		# patch gcc/g++
		echo "Patch $gcc_name ..."
		patch -d $gcc_srcdir -p1 < $gcc_patch

		if [[ $? != 0 ]]; then
			echo "Can't apply patches!"
			exit 1
		fi
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

	$gcc_srcdir/configure --target=$gcc_target --prefix=$prefix \
			   $gcc_sysroot_arg \
			   --enable-languages=c \
			   --with-sysroot=$prefix/$gcc_target \
			   --disable-shared \
			   --disable-nls \
			   --with-newlib

	# build it
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
	b) # binutils package + patches
		binutils_srcdir=`parse_string $OPTARG 1`
		binutils_patch=`parse_string $OPTARG 2`

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

	c) # gcc core + patches
		gcc_core_srcdir=`parse_string $OPTARG 1`
		gcc_core_patch=`parse_string $OPTARG 2`

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

	g) # gcc + patches
		gcc_srcdir=`parse_string $OPTARG 1`
		gcc_patch=`parse_string $OPTARG 2`

		if [ -z  $gcc_srcdir ]; then
			echo "Empty argument (missing gcc source)!"
			exit 1
		fi

		gcc_srcdir=`abspath $gcc_srcdir`
		gcc_name=`basename $gcc_srcdir`

		# build dircetory path
		gcc_builddir=$workdir/${gcc_name}-build
		;;

	l) # glibc + patches
		glibc_srcdir=`parse_string $OPTARG 1`
		glibc_patch=`parse_string $OPTARG 2`

		if [ -z  $glibc_srcdir ]; then
			echo "Empty argument (missing glibc source)!"
			exit 1
		fi

		glibc_srcdir=`abspath $glibc_srcdir`
		glibc_name=`basename $glibc_srcdir`

		# build dircetory path
		glibc_headers_build=$workdir/${glibc_name}-headers-build
		glibc_builddir=$workdir/${glibc_name}-build
		;;

	n) # newlib + patches
		newlib_srcdir=`parse_string $OPTARG 1`
		newlib_patch=`parse_string $OPTARG 2`

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
echo $gcc_core_prefix_link/bin
PATH="$prefix/bin:$gcc_core_prefix_link/bin:${PATH}"
export PATH

echo "Creating installation directory ..."

mkdir -p ${prefix}/${target}

# spiffy new sysroot way.  libraries split between
# prefix/target/sys-root/lib and prefix/target/sys-root/usr/lib
sysroot=${prefix}/${target}/sys-root
header_dir=${sysroot}/usr/include
binutils_sysroot_arg="--with-sysroot=${sysroot}"
gcc_sysroot_arg="--with-sysroot=${sysroot}"
gcc_core_sysroot_arg=${gcc_sysroot_arg}
glibc_sysroot_arg=""

# glibc's prefix must be exactly /usr, else --with-sysroot'd
# gcc will get confused when $sysroot/usr/include is not present
# Note: --prefix=/usr is magic!  See http://www.gnu.org/software/libc/FAQ.html#s-2.2

# Make lib directory in sysroot, else the ../lib64 hack used by 32 -> 64 bit
# crosscompilers won't work, and build of final gcc will fail with
#  "ld: cannot open crti.o: No such file or directory"
mkdir -p $sysroot/lib
mkdir -p $sysroot/usr/lib

mkdir -p ${header_dir}

# install system headers from kernel directoru
install_system_headers x${KERNELDIR} x${header_dir}

### Build binutils
if [ -n "$binutils_builddir" ]; then
	build_binutils
fi

## gcc 3.x may require this
## FIXME: use gcc 4.x only
# build_glibc_headers
# exit 0

### Build a core gcc (just enough to build glibc)
if [ -n "$gcc_core_builddir" ]; then
	build_gcc_core
fi

### Build a glibc
if [ -n "$glibc_builddir" ]; then
	build_glibc
fi

exit 0

### Build a newlib
if [ -n "$newlib_builddir" ]; then
	build_newlib
fi

### Build full cross compiler
if [ -n "$gcc_builddir" ]; then
	build_gcc_full
fi

echo "Done"

exit 0
