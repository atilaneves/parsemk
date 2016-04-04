# This Makefile snippet detects the OS and the architecture MODEL
# Keep this file in sync between druntime, phobos, and dmd repositories!

ifeq (,$(OS))
  uname_S:=$(shell uname -s)
  ifeq (Darwin,$(uname_S))
    OS:=osx
  endif
  ifeq (Linux,$(uname_S))
    OS:=linux
  endif
  ifeq (FreeBSD,$(uname_S))
    OS:=freebsd
  endif
  ifeq (NetBSD,$(uname_S))
    OS:=netbsd
  endif
  ifeq (OpenBSD,$(uname_S))
    OS:=openbsd
  endif
  ifeq (Solaris,$(uname_S))
    OS:=solaris
  endif
  ifeq (SunOS,$(uname_S))
    OS:=solaris
  endif
#   ifeq (,$(OS))
# # TODO    $(error Unrecognized or unsupported OS for uname: $(uname_S))
#   endif
endif

# When running make from XCode it may set environment var OS=MACOS.
# Adjust it here:
ifeq (MACOS,$(OS))
  OS:=osx
endif

ifeq (,$(MODEL))
  # ifeq ($(OS), solaris)
  #   uname_M:=$(shell isainfo -n)
  # else
  #   uname_M:=$(shell uname -m)
  # endif
  ifeq ($(OS),solaris)
  #ifeq (,$(solaris))
    uname_M:=foo
  endif
endif

MODEL_FLAG:=-m$(MODEL)
