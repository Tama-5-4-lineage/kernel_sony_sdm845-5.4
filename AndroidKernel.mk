# Android makefile to build the kernel as part of the Android build.
# Adapted for the Sony SDM845 (tama) 5.4 tree (AOSP build.config style kernel).

PERL		= perl

KERNEL_TARGET := $(strip $(INSTALLED_KERNEL_TARGET))
ifeq ($(KERNEL_TARGET),)
INSTALLED_KERNEL_TARGET := $(PRODUCT_OUT)/kernel
endif

TARGET_KERNEL_ARCH := $(strip $(TARGET_KERNEL_ARCH))
ifeq ($(TARGET_KERNEL_ARCH),)
KERNEL_ARCH := arm64
else
KERNEL_ARCH := $(TARGET_KERNEL_ARCH)
endif

# defconfig comes from the device tree (e.g. aosp_tama_defconfig)
KERNEL_DEFCONFIG := $(strip $(TARGET_KERNEL_CONFIG))

KERNEL_CROSS_COMPILE := aarch64-linux-gnu-

# LLVM / clang when the device tree asks for it
KERNEL_MAKE_ENV := $(strip $(TARGET_KERNEL_MAKE_ENV))
ifeq ($(TARGET_KERNEL_CLANG_COMPILE),true)
KERNEL_MAKE_ENV += LLVM=1 LLVM_IAS=1
endif

KERNEL_OUT := $(TARGET_OUT_INTERMEDIATES)/kernel/$(TARGET_KERNEL_VERSION)
KERNEL_CONFIG := $(KERNEL_OUT)/.config

KERNEL_MODULES_INSTALL ?= system
KERNEL_MODULES_OUT ?= $(PRODUCT_OUT)/$(KERNEL_MODULES_INSTALL)/lib/modules

TARGET_PREBUILT_INT_KERNEL := $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/Image.gz-dtb

KERNEL_MAKE := $(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(abspath $(KERNEL_OUT)) \
	$(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE)

.PHONY: FORCE
FORCE:

ifeq ($(KERNEL_DEFCONFIG)$(wildcard $(KERNEL_CONFIG)),)
$(error Kernel configuration not defined (TARGET_KERNEL_CONFIG), cannot build kernel)
endif

$(KERNEL_OUT):
	mkdir -p $(KERNEL_OUT)

$(KERNEL_CONFIG): $(KERNEL_OUT)
	$(KERNEL_MAKE) $(KERNEL_DEFCONFIG)

$(TARGET_PREBUILT_INT_KERNEL): $(KERNEL_OUT) $(KERNEL_CONFIG) FORCE
	$(hide) echo "Building kernel ($(KERNEL_DEFCONFIG))..."
	$(KERNEL_MAKE) -j$(shell nproc) Image.gz-dtb dtbs
	$(hide) echo "Building kernel modules..."
	$(KERNEL_MAKE) -j$(shell nproc) modules
	$(KERNEL_MAKE) INSTALL_MOD_PATH=$(abspath $(KERNEL_MODULES_OUT)/../../) \
		INSTALL_MOD_STRIP=1 modules_install
	$(hide) if [ -d "$(KERNEL_MODULES_OUT)" ]; then \
		mdpath=`find $(KERNEL_MODULES_OUT) -type f -name modules.dep`; \
		if [ "$$mdpath" != "" ]; then \
			mpath=`dirname $$mdpath`; \
			ko=`find $$mpath/kernel -type f -name *.ko`; \
			for i in $$ko; do mv $$i $(KERNEL_MODULES_OUT)/; done; \
			rm -rf $$mpath; \
		fi; \
	fi

$(INSTALLED_KERNEL_TARGET): $(TARGET_PREBUILT_INT_KERNEL)
	$(copy-file-to-target)

# --- DTBO image (needed when BUILD_KERNEL=true; device tree overlays) ---
INSTALLED_DTBOIMAGE_TARGET := $(PRODUCT_OUT)/dtbo-$(TARGET_DEVICE).img
MKDTIMG ?= $(abspath system/libufdt/utils/src/mkdtboimg.py)

$(INSTALLED_DTBOIMAGE_TARGET): $(INSTALLED_KERNEL_TARGET)
	$(hide) echo "Making DTBO image: $@"
	$(hide) if [ -f $(MKDTIMG) ]; then \
		$(MKDTIMG) create $@ $$(find $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/dts -name '*.dtbo'); \
	fi

droidcore: $(INSTALLED_DTBOIMAGE_TARGET)
