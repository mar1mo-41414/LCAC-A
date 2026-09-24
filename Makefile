ARCHS = arm64
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = LCAutoClearArrows

LCAutoClearArrows_FILES = $(wildcard Sources/*.m)
LCAutoClearArrows_CFLAGS = -fobjc-arc -Wall -ISources
LCAutoClearArrows_FRAMEWORKS = UIKit Foundation QuartzCore
LCAutoClearArrows_LIBRARY_EXTENSION = .dylib
LCAutoClearArrows_INSTALL_PATH = /usr/lib

include $(THEOS_MAKE_PATH)/library.mk
