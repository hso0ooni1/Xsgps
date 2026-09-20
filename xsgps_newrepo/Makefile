ARCHS := arm64
TARGET := iphone:clang:latest:16.0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME := XsGpS

XsGpS_FILES := $(sort $(wildcard Source/*.m))
XsGpS_CFLAGS := -fobjc-arc -Wall -Wextra -Wno-error -Wno-nullability-completeness -Wno-unused-parameter -Wno-deprecated-declarations -ISource
XsGpS_FRAMEWORKS := Foundation UIKit CoreLocation MapKit Security
XsGpS_LDFLAGS := -install_name @executable_path/Frameworks/XsGpS.dylib

include $(THEOS)/makefiles/library.mk
