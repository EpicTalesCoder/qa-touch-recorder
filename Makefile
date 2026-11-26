TARGET := iphone:clang:latest:16.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME := QATouchRecorder
QATouchRecorder_FILES := \
	src/QATouchScriptModel.m \
	src/QATouchRecorderEngine.m \
	src/QATouchOverlayUI.m \
	src/QATouchEntry.m
QATouchRecorder_FRAMEWORKS := UIKit Foundation CoreGraphics QuartzCore
QATouchRecorder_CFLAGS := -fobjc-arc -fvisibility=hidden -Wall -Wextra -Wno-deprecated-declarations
QATouchRecorder_LDFLAGS := -Wl,-install_name,@rpath/QATouchRecorder.dylib
QATouchRecorder_INSTALL_PATH := @rpath

include $(THEOS)/makefiles/library.mk
