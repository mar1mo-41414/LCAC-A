ARCHS = arm64
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = LCAC-A

LCAC-A_FILES = $(wildcard Sources/*.m)
LCAC-A_CFLAGS = -fobjc-arc -Wall -ISources
LCAC-A_FRAMEWORKS = UIKit Foundation QuartzCore
LCAC-A_LIBRARY_EXTENSION = .dylib
LCAC-A_INSTALL_PATH = /usr/lib

include $(THEOS_MAKE_PATH)/library.mk
