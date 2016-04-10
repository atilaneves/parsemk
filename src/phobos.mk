# Makefile to build linux D runtime library libphobos2.a and its unit test
#
# make => makes release build of the library
#
# make clean => removes all targets built by the makefile
#
# make zip => creates a zip file of all the sources (not targets)
# referred to by the makefile, including the makefile
#
# make BUILD=debug => makes debug build of the library
#
# make unittest => builds all unittests (for debug AND release) and runs them
#
# make BUILD=debug unittest => builds all unittests (for debug) and runs them
#
# make html => makes html documentation
#
# make install => copies library to /usr/lib
#
# make std/somemodule.test => only builds and unittests std.somemodule
#

################################################################################
# Configurable stuff, usually from the command line
#
# OS can be linux, win32, win32wine, osx, or freebsd. The system will be
# determined by using uname

QUIET:=

include src/osmodel.mak

# Default to a release built, override with BUILD=debug
ifeq (,$(BUILD))
BUILD_WAS_SPECIFIED=0
BUILD=release
else
BUILD_WAS_SPECIFIED=1
endif

ifneq ($(BUILD),release)
    ifneq ($(BUILD),debug)
        $(error Unrecognized BUILD=$(BUILD), must be 'debug' or 'release')
    endif
endif

override PIC:=$(if $(PIC),-fPIC,)

# Configurable stuff that's rarely edited
INSTALL_DIR = ../install
DRUNTIME_PATH = ../druntime
ZIPFILE = phobos.zip
ROOT_OF_THEM_ALL = generated
ROOT = $(ROOT_OF_THEM_ALL)/$(OS)/$(BUILD)/$(MODEL)
# Documentation-related stuff
DOCSRC = ../dlang.org
WEBSITE_DIR = ../web
DOC_OUTPUT_DIR = $(WEBSITE_DIR)/phobos-prerelease
BIGDOC_OUTPUT_DIR = /tmp
SRC_DOCUMENTABLES = index.d $(addsuffix .d,$(STD_MODULES) \
	$(EXTRA_DOCUMENTABLES))
STDDOC = $(DOCSRC)/html.ddoc $(DOCSRC)/dlang.org.ddoc $(DOCSRC)/std_navbar-prerelease.ddoc $(DOCSRC)/std.ddoc $(DOCSRC)/macros.ddoc $(DOCSRC)/.generated/modlist-prerelease.ddoc
BIGSTDDOC = $(DOCSRC)/std_consolidated.ddoc $(DOCSRC)/macros.ddoc
# Set DDOC, the documentation generator
DDOC=$(DMD) -conf= $(MODEL_FLAG) -w -c -o- -version=StdDdoc \
	-I$(DRUNTIME_PATH)/import $(DMDEXTRAFLAGS)
# Set DRUNTIME name and full path
ifneq (,$(DRUNTIME))
	CUSTOM_DRUNTIME=1
endif
ifeq (,$(findstring win,$(OS)))
	DRUNTIME = $(DRUNTIME_PATH)/generated/$(OS)/$(BUILD)/$(MODEL)/libdruntime.a
	DRUNTIMESO = $(basename $(DRUNTIME)).so.a
else
	DRUNTIME = $(DRUNTIME_PATH)/lib/druntime.lib
endif

# Set CC and DMD
ifeq ($(OS),win32wine)
	CC = wine dmc.exe
	DMD = wine dmd.exe
	RUN = wine
else
	DMD = ../dmd/src/dmd
	ifeq ($(OS),win32)
		CC = dmc
	else
		CC = cc
	endif
	RUN =
endif

# Set CFLAGS
CFLAGS=$(MODEL_FLAG) -fPIC -DHAVE_UNISTD_H
# Set DFLAGS
DFLAGS=-conf= -I$(DRUNTIME_PATH)/import $(DMDEXTRAFLAGS) -w -dip25 $(MODEL_FLAG) $(PIC)
ifeq ($(BUILD),debug)
	DFLAGS += -g -debug
else
	DFLAGS += -O -release
endif

# Set DOTOBJ and DOTEXE
ifeq (,$(findstring win,$(OS)))
	DOTOBJ:=.o
	DOTEXE:=
	PATHSEP:=/
else
	DOTOBJ:=.obj
	DOTEXE:=.exe
	PATHSEP:=$(shell echo "\\")
endif

LINKDL:=$(if $(findstring $(OS),linux),-L-ldl,)

# use timelimit to avoid deadlocks if available
TIMELIMIT:=$(if $(shell which timelimit 2>/dev/null || true),timelimit -t 60 ,)

# Set VERSION, where the file is that contains the version string
VERSION=../dmd/VERSION

# Set LIB, the ultimate target
ifeq (,$(findstring win,$(OS)))
	LIB:=$(ROOT)/libphobos2.a
	# 2.064.2 => libphobos2.so.0.64.2
	# 2.065 => libphobos2.so.0.65.0
	# MAJOR version is 0 for now, which means the ABI is still unstable
	MAJOR:=0
	MINOR:=$(shell awk -F. '{ print int($$2) }' $(VERSION))
	PATCH:=$(shell awk -F. '{ print int($$3) }' $(VERSION))
	# SONAME doesn't use patch level (ABI compatible)
	SONAME:=libphobos2.so.$(MAJOR).$(MINOR)
	LIBSO:=$(ROOT)/$(SONAME).$(PATCH)
else
	LIB:=$(ROOT)/phobos.lib
endif

################################################################################
MAIN = $(ROOT)/emptymain.d

# Given one or more packages, returns their respective libraries
P2LIB=$(addprefix $(ROOT)/libphobos2_,$(addsuffix $(DOTLIB),$(subst /,_,$1)))
# Given one or more packages, returns the modules they contain
P2MODULES=$(foreach P,$1,$(addprefix $P/,$(PACKAGE_$(subst /,_,$P))))

# Packages in std. Just mention the package name here. The contents of package
# xy/zz is in variable PACKAGE_xy_zz. This allows automation in iterating
# packages and their modules.
STD_PACKAGES = std $(addprefix std/,\
  algorithm container digest experimental/allocator \
  experimental/allocator/building_blocks experimental/logger \
  experimental/ndslice \
  net \
  range regex)

# Modules broken down per package

PACKAGE_std = array ascii base64 bigint bitmanip compiler complex concurrency \
  concurrencybase conv cstream csv datetime demangle encoding exception file format \
  functional getopt json math mathspecial meta mmfile numeric \
  outbuffer parallelism path process random signals socket socketstream stdint \
  stdio stdiobase stream string system traits typecons typetuple uni \
  uri utf uuid variant xml zip zlib
PACKAGE_std_algorithm = comparison iteration mutation package searching setops \
  sorting
PACKAGE_std_container = array binaryheap dlist package rbtree slist util
PACKAGE_std_digest = crc digest hmac md ripemd sha
PACKAGE_std_experimental_logger = core filelogger \
  nulllogger multilogger package
PACKAGE_std_experimental_allocator = \
  common gc_allocator mallocator mmap_allocator package showcase typed
PACKAGE_std_experimental_allocator_building_blocks = \
  affix_allocator allocator_list bucketizer \
  fallback_allocator free_list free_tree bitmapped_block \
  kernighan_ritchie null_allocator package quantizer \
  region scoped_allocator segregator stats_collector
PACKAGE_std_experimental_ndslice = package iteration selection slice
PACKAGE_std_net = curl isemail
PACKAGE_std_range = interfaces package primitives
PACKAGE_std_regex = package $(addprefix internal/,generator ir parser \
  backtracking kickstart tests thompson)

# Modules in std (including those in packages)
STD_MODULES=$(call P2MODULES,$(STD_PACKAGES))

# OS-specific D modules
EXTRA_MODULES_LINUX := $(addprefix std/c/linux/, linux socket)
EXTRA_MODULES_OSX := $(addprefix std/c/osx/, socket)
EXTRA_MODULES_FREEBSD := $(addprefix std/c/freebsd/, socket)
EXTRA_MODULES_WIN32 := $(addprefix std/c/windows/, com stat windows		\
		winsock) $(addprefix std/windows/, charset iunknown syserror)

# Other D modules that aren't under std/
EXTRA_MODULES_COMMON := $(addprefix etc/c/,curl odbc/sql odbc/sqlext \
  odbc/sqltypes odbc/sqlucode sqlite3 zlib) $(addprefix std/c/,fenv locale \
  math process stdarg stddef stdio stdlib string time wcharh)

EXTRA_DOCUMENTABLES := $(EXTRA_MODULES_LINUX) $(EXTRA_MODULES_WIN32) $(EXTRA_MODULES_COMMON)

EXTRA_MODULES_INTERNAL := $(addprefix			\
	std/internal/digest/, sha_SSSE3 ) $(addprefix \
	std/internal/math/, biguintcore biguintnoasm biguintx86	\
	gammafunction errorfunction) $(addprefix std/internal/, \
	cstring processinit unicode_tables scopebuffer\
	unicode_comp unicode_decomp unicode_grapheme unicode_norm) \
	$(addprefix std/internal/test/, dummyrange) \
	$(addprefix std/experimental/ndslice/, internal) \
	$(addprefix std/algorithm/, internal)

EXTRA_MODULES += $(EXTRA_DOCUMENTABLES) $(EXTRA_MODULES_INTERNAL)

# Aggregate all D modules relevant to this build
D_MODULES = $(STD_MODULES) $(EXTRA_MODULES)

# Add the .d suffix to the module names
D_FILES = $(addsuffix .d,$(D_MODULES))
# Aggregate all D modules over all OSs (this is for the zip file)
ALL_D_FILES = $(addsuffix .d, $(STD_MODULES) $(EXTRA_MODULES_COMMON) \
  $(EXTRA_MODULES_LINUX) $(EXTRA_MODULES_OSX) $(EXTRA_MODULES_FREEBSD) \
  $(EXTRA_MODULES_WIN32) $(EXTRA_MODULES_INTERNAL)) \
  std/internal/windows/advapi32.d \
  std/windows/registry.d std/c/linux/pthread.d std/c/linux/termios.d \
  std/c/linux/tipc.d

# C files to be part of the build
C_MODULES = $(addprefix etc/c/zlib/, adler32 compress crc32 deflate	\
	gzclose gzlib gzread gzwrite infback inffast inflate inftrees trees uncompr zutil)

OBJS = $(addsuffix $(DOTOBJ),$(addprefix $(ROOT)/,$(C_MODULES)))

MAKEFILE = $(firstword $(MAKEFILE_LIST))

# build with shared library support (defaults to true on supported platforms)
SHARED=$(if $(findstring $(OS),linux freebsd),1,)

################################################################################
# Rules begin here
################################################################################

# Main target (builds the dll on linux, too)
ifeq (1,$(SHARED))
all : lib dll
else
all : lib
endif


################################################################################
# Patterns begin here
################################################################################

#.PHONY: lib dll
lib: $(LIB)
dll: $(ROOT)/libphobos2.so

$(ROOT)/%$(DOTOBJ): %.c
	@[ -d $(dir $@) ] || mkdir -p $(dir $@) || [ -d $(dir $@) ]
	$(CC) -c $(CFLAGS) $< -o$@

$(LIB): $(OBJS) $(ALL_D_FILES) $(DRUNTIME)
	$(DMD) $(DFLAGS) -lib -of$@ $(DRUNTIME) $(D_FILES) $(OBJS)
