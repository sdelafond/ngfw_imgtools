## overridables
REPOSITORY ?= buster
DISTRIBUTION ?= current

## variables
IMGTOOLS_DIR := $(shell readlink -f $(shell dirname $(MAKEFILE_LIST)))
PKGTOOLS_DIR := $(IMGTOOLS_DIR)/../ngfw_pkgtools
PKGS := bf-utf-source debiandoc-sgml genext2fs glibc-pic grub-common grub-efi-amd64-bin isolinux libbogl-dev libnewt-pic librsvg2-bin libslang2-pic mklibs module-init-tools pxelinux syslinux-utils tofrodos win32-loader xorriso
ARCH := $(shell dpkg-architecture -qDEB_BUILD_ARCH)
DEBVERSION := 10.0
KERNELS_i386 := "linux-image-4.19.0-6-untangle-686-pae"
KERNELS_amd64 := "linux-image-4.19.0-6-untangle-amd64"
VERSION = $(shell cat $(PKGTOOLS_DIR)/resources/VERSION)
ISO_IMAGE := +FLAVOR+-$(VERSION)_$(REPOSITORY)_$(ARCH)_$(DISTRIBUTION)_$(shell date --iso-8601=seconds)_$(shell hostname -s).iso
USB_IMAGE := $(subst .iso,.img,$(ISO_IMAGE))
IMAGES_DIR := /data/untangle-images-$(REPOSITORY)
MOUNT_SCRIPT := /data/image-manager/mounts.py
NETBOOT_HOST := netboot-server
NETBOOT_DIR_TXT := $(IMGTOOLS_DIR)/d-i/build/dest/netboot/debian-installer/$(ARCH)
NETBOOT_DIR_GTK := $(IMGTOOLS_DIR)/d-i/build/dest/netboot/gtk/debian-installer/$(ARCH)
NETBOOT_INITRD_TXT := $(NETBOOT_DIR_TXT)/initrd.gz
NETBOOT_INITRD_GTK := $(NETBOOT_DIR_GTK)/initrd.gz
NETBOOT_KERNEL := $(NETBOOT_DIR_TXT)/linux
BOOT_IMG := $(IMGTOOLS_DIR)/d-i/build/dest/hd-media/boot.img.gz
PROFILES_DIR := $(IMGTOOLS_DIR)/profiles
COMMON_PRESEED :=  $(PROFILES_DIR)/common.preseed
AUTOPARTITION_PRESEED :=  $(PROFILES_DIR)/auto-partition.preseed
UNTANGLE_PRESEED := $(PROFILES_DIR)/untangle.preseed
NETBOOT_PRESEED := $(PROFILES_DIR)/netboot.preseed
NETBOOT_PRESEED_FINAL := $(NETBOOT_PRESEED).$(ARCH)
NETBOOT_PRESEED_EXPERT := $(PROFILES_DIR)/netboot.expert.preseed.$(ARCH)
NETBOOT_PRESEED_EXTRA := $(NETBOOT_PRESEED).extra
DEFAULT_PRESEED_FINAL := $(PROFILES_DIR)/default.preseed
DEFAULT_PRESEED_EXPERT := $(PROFILES_DIR)/expert.preseed
DEFAULT_PRESEED_EXTRA := $(DEFAULT_PRESEED_FINAL).extra
CONF_FILE := $(PROFILES_DIR)/default.conf
CONF_FILE_TEMPLATE := $(CONF_FILE).template
CUSTOMSIZE := $(shell echo $$(( 680 * 1024 * 1024 / 2048 )) ) # from MB to 2kB blocks
DEBIAN_INSTALLER_PATCH := $(IMGTOOLS_DIR)/patches/d-i.patch
DEBIAN_CD_PATCH := $(IMGTOOLS_DIR)/patches/debian-cd.patch
DEBIAN_PKGS_PATCH := $(IMGTOOLS_DIR)/patches/installer-pkgs.patch
DEBIAN_PATCHES := $(DEBIAN_INSTALLER_PATCH) $(DEBIAN_CD_PATCH) $(DEBIAN_PKGS_PATCH)
DEBIAN_PATCH_STAMP := patch-stamp

## main section
all: # do nothing by default

## d-i section
d-i/patch: $(DEBIAN_PATCH_STAMP)
$(DEBIAN_PATCH_STAMP):
	for p in $(DEBIAN_PATCHES) ; do \
	  patch -p0 < $$p ; \
	done
	touch $@

d-i/unpatch:
	if [ -f $(DEBIAN_PATCH_STAMP) ] ; then \
	  for p in $(DEBIAN_PATCHES) ; do \
	    patch -p0 -R < $$p ; \
	  done ; \
	  rm -f $(DEBIAN_PATCH_STAMP) ; \
	fi

## iso section
repoint-stable:
	$(PKGTOOLS_DIR)/package-server-proxy.sh $(PKGTOOLS_DIR)/create-di-links.sh $(REPOSITORY) $(DISTRIBUTION)

iso/conf:
	perl -pe 's|\+IMGTOOLS_DIR\+|'$(IMGTOOLS_DIR)'|g' $(CONF_FILE_TEMPLATE) >| $(CONF_FILE)

	cat $(COMMON_PRESEED) $(AUTOPARTITION_PRESEED) $(NETBOOT_PRESEED_EXTRA) $(UNTANGLE_PRESEED) | perl -pe 's|\+VERSION\+|'$(VERSION)'|g ; s|\+ARCH\+|'$(ARCH)'|g ; s|\+REPOSITORY\+|'$(REPOSITORY)'|g ; s|\+KERNELS\+|'$(KERNELS_$(ARCH))'|g ; s/^(d-i preseed\/early_command string anna-install.*)/#$1/' >| $(NETBOOT_PRESEED_FINAL)
	cat $(COMMON_PRESEED) $(AUTOPARTITION_PRESEED) $(DEFAULT_PRESEED_EXTRA) | perl -pe 's|\+VERSION\+|'$(VERSION)'|g ; s|\+ARCH\+|'$(ARCH)'|g ; s|\+REPOSITORY\+|'$(REPOSITORY)'|g ; s|\+KERNELS\+|'$(KERNELS_$(ARCH))'|g' >| $(DEFAULT_PRESEED_FINAL)
	cat $(COMMON_PRESEED) $(NETBOOT_PRESEED_EXTRA) $(UNTANGLE_PRESEED) | perl -pe 's|\+VERSION\+|'$(VERSION)'|g ; s|\+ARCH\+|'$(ARCH)'|g ; s|\+REPOSITORY\+|'$(REPOSITORY)'|g ; s|\+KERNELS\+|'$(KERNELS_$(ARCH))'|g ; s/^(d-i preseed\/early_command string anna-install.*)/#$1/' >| $(NETBOOT_PRESEED_EXPERT)
	cat $(COMMON_PRESEED) $(DEFAULT_PRESEED_EXTRA) | perl -pe 's|\+VERSION\+|'$(VERSION)'|g ; s|\+ARCH\+|'$(ARCH)'|g ; s|\+REPOSITORY\+|'$(REPOSITORY)'|g ; s|\+KERNELS\+|'$(KERNELS_$(ARCH))'|g' >| $(DEFAULT_PRESEED_EXPERT)

iso/dependencies:
	apt install -y simple-cdd dose-distcheck

iso/%-image: repoint-stable iso/dependencies iso/conf
	$(eval flavor := $*)
	$(eval iso_dir := /tmp/untangle-images-$(REPOSITORY)-$(DISTRIBUTION)-$(flavor))
	mkdir -p $(iso_dir)
	export TMP_DIR=$(shell mktemp -d /tmp/imgtools-$(DISTRIBUTION)-$(flavor)-XXXXXX) ; \
	cd $${TMP_DIR} ; \
	cp -rl $(IMGTOOLS_DIR)/* . 2> /dev/null ; \
	export CODENAME=$(REPOSITORY) DEBVERSION=$(DEBVERSION) OUT=$(iso_dir) ; \
	export CDNAME=$(flavor) DISKTYPE=CUSTOM CUSTOMSIZE=$(CUSTOMSIZE) ; \
	build-simple-cdd --keyring /usr/share/keyrings/untangle-archive-keyring.gpg --force-root --auto-profiles default,untangle,$(flavor) --profiles untangle,$(flavor),expert --debian-mirror http://package-server/public/$(REPOSITORY)/ --security-mirror http://package-server/public/$(REPOSITORY)/ --dist $(REPOSITORY) --require-optional-packages --mirror-tools reprepro --extra-udeb-dist $(DISTRIBUTION) --do-mirror --verbose --logfile $(IMGTOOLS_DIR)/simplecdd.log  ; \
	rm -fr $${TMP_DIR}
	mv $(iso_dir)/$(flavor)-$(DEBVERSION)*-$(ARCH)-*1.iso $(iso_dir)/$(subst +FLAVOR+,$(flavor),$(ISO_IMAGE))

iso/%-clean:
	rm -fr $(IMGTOOLS_DIR)/tmp /tmp/untangle-images-$(REPOSITORY)-$(DISTRIBUTION)-$*

## usb-section
usb/%-image:
	$(eval flavor := $*)
	$(eval iso_dir := /tmp/untangle-images-$(REPOSITORY)-$(DISTRIBUTION)-$(flavor))
	$(eval iso_image := $(shell ls --sort=time $(iso_dir)/*$(VERSION)*$(REPOSITORY)*$(ARCH)*$(DISTRIBUTION)*.iso | head -1))
	$(IMGTOOLS_DIR)/make_usb.sh $(BOOT_IMG) $(iso_image) $(iso_dir)/$(subst +FLAVOR+,$(flavor),$(USB_IMAGE)) $(flavor)

## ova-section
ova/%-image:
	make -C $(IMGTOOLS_DIR)/ova FLAVOR=$* image
ova/%-push:
	make -C $(IMGTOOLS_DIR)/ova FLAVOR=$* push
ova/%-clean:
	make -C $(IMGTOOLS_DIR)/ova FLAVOR=$* clean

## cloud-section
# cloud/<provider>/<license> -> make LICENSE=<license> <provider>-image
cloud/%-image:
	$(eval license := $(shell basename $*))
	$(eval provider := $(shell dirname $(subst cloud/,"",$*)))
	make -C $(IMGTOOLS_DIR)/cloud LICENSE=$(license) $(provider)-image
cloud/%-push:
	$(eval license := $(shell basename $*))
	$(eval provider := $(shell dirname $(subst cloud/,"",$*)))
	make -C $(IMGTOOLS_DIR)/cloud LICENSE=$(license) $(provider)-push
cloud/%-clean:
	$(eval license := $(shell basename $*))
	$(eval provider := $(shell dirname $(subst cloud/,"",$*)))
	make -C $(IMGTOOLS_DIR)/cloud LICENSE=$(license) clean

iso/%-push: # pushes the most recent images
	$(eval iso_dir := /tmp/untangle-images-$(REPOSITORY)-$(DISTRIBUTION)-$*)
	$(eval iso_image := $(shell ls --sort=time $(iso_dir)/*$(VERSION)*$(REPOSITORY)*$(ARCH)*$(DISTRIBUTION)*.iso | head -1))
	$(eval usb_image := $(shell ls --sort=time $(iso_dir)/*$(VERSION)*$(REPOSITORY)*$(ARCH)*$(DISTRIBUTION)*.img | head -1))
	$(eval timestamp := $(shell echo $(iso_image) | perl -pe 's/.*(\d{4}(-\d{2}){2}T(\d{2}:?){3}).*/$$1/'))
	ssh $(NETBOOT_HOST) "sudo python $(MOUNT_SCRIPT) new $(VERSION) $(timestamp) $(ARCH) $(REPOSITORY)"
	scp $(iso_image) $(usb_image) $(NETBOOT_PRESEED_FINAL) $(NETBOOT_PRESEED_EXPERT) $(NETBOOT_HOST):$(IMAGES_DIR)/$(VERSION)
	scp $(NETBOOT_INITRD_TXT) $(NETBOOT_HOST):$(IMAGES_DIR)/$(VERSION)/initrd-$(ARCH)-txt.gz
	scp $(NETBOOT_INITRD_GTK) $(NETBOOT_HOST):$(IMAGES_DIR)/$(VERSION)/initrd-$(ARCH)-gtk.gz
	scp $(NETBOOT_KERNEL) $(NETBOOT_HOST):$(IMAGES_DIR)/$(VERSION)/linux-$(ARCH)

	ssh $(NETBOOT_HOST) "sudo python $(MOUNT_SCRIPT) all $(VERSION) foo $(ARCH) $(REPOSITORY)"

## firmware section

# the next 4 rules are generic ones meant for firmware images; they
# take something like "buffalo/wzr1900dhp-image" and make it into
# "make -C firmware/buffalo-wzr1900dhp image"

%-image:
	make -C $(IMGTOOLS_DIR)/firmware/$(subst /,-,$*) image
%-rootfs:
	make -C $(IMGTOOLS_DIR)/firmware/$(subst /,-,$*) rootfs
%-push:
	make -C $(IMGTOOLS_DIR)/firmware/$(subst /,-,$*) push
%-clean:
	make -C $(IMGTOOLS_DIR)/firmware/$(subst /,-,$*) clean
