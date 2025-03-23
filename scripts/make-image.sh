#!/bin/sh

TARGET_DIR=$(pwd)/target
TARGET_ESP_DIR=${TARGET_DIR}/boot
TARGET_DISK=$(pwd)/disk.img
OSNAME=alpine
REPOPATH=${TARGET_DIR}/ostree/repo
OSTREE_BRANCH=foo
OSTREE_REMOTE_NAME=${OSNAME}
OSTREE_SERVER_URL=http://192.168.1.133:8080/repo/

echo "Prepare storage"
dd if=/dev/zero of=${TARGET_DISK} bs=16M count=64

PART_CMD="start=2048, size=500MiB, type=83, bootable\n"
PART_CMD=${PART_CMD}"type=83"
echo -e ${PART_CMD} | sfdisk ${TARGET_DISK}

# https://github.com/damianperera/mount-image-action/blob/v1/action.yml#L36
kpartx="$(kpartx -avs ${TARGET_DISK})" || echo 1>&2 "ERROR: could not create loop devices for image"
echo $kpartx
blockDevices=$(echo $kpartx | grep -o 'loop.p.')
set -- ${blockDevices}
esp=/dev/mapper/$1
root=/dev/mapper/$2

echo "ESP: ${esp}"
echo "Root: ${root}"

mkfs.ext4 -L BOOT ${esp}
mkfs.ext4 -L ROOT ${root}

mkdir -p ${TARGET_DIR}
mount -t ext4 ${root} ${TARGET_DIR}
mkdir -p ${TARGET_ESP_DIR}
mount -t ext4 ${esp} ${TARGET_ESP_DIR}

echo "Deploy OSTree filesystem into the storage"
ostree admin init-fs "${TARGET_DIR}"
ostree admin --sysroot="${TARGET_DIR}" os-init ${OSNAME}
ostree --repo="${REPOPATH}" remote add ${OSTREE_REMOTE_NAME} ${OSTREE_SERVER_URL} ${OSTREE_BRANCH} --no-gpg-verify
ostree --repo="${REPOPATH}" pull ${OSTREE_REMOTE_NAME} ${OSTREE_BRANCH}
ostree admin deploy --sysroot="${TARGET_DIR}" --os=${OSNAME} --karg=rw --karg=console=ttyS0 ${OSTREE_REMOTE_NAME}:${OSTREE_BRANCH}
OSTREE_CURRENT_DEPLOYMENT=$(ostree admin --sysroot="${TARGET_DIR}" status | awk '{print $2; exit}')

echo "Prepare Boot Partitionn"
OSTREE_CURRENT_ROOT=${TARGET_DIR}/ostree/deploy/${OSNAME}/deploy/${OSTREE_CURRENT_DEPLOYMENT}
dd bs=440 count=1 conv=notrunc if=${OSTREE_CURRENT_ROOT}/usr/share/syslinux/mbr.bin of=${TARGET_DISK}
${OSTREE_CURRENT_ROOT}/sbin/extlinux --install ${TARGET_ESP_DIR}
SYSLINUX_FIRMWARES="libcom32.c32 libutil.c32 mboot.c32 menu.c32 vesamenu.c32"
for f in ${SYSLINUX_FIRMWARES}; do
  cp ${OSTREE_CURRENT_ROOT}/usr/share/syslinux/$f ${TARGET_ESP_DIR}/
done
SYSLINUX_CFG=${TARGET_ESP_DIR}/syslinux.cfg
cat << EOF > ${SYSLINUX_CFG}
DEFAULT menu.c32
PROMPT 0
MENU TITLE Alpine/Linux Boot Menu
MENU AUTOBOOT Alpine will be booted automatically in # seconds
TIMEOUT 10
EOF
cat ${TARGET_ESP_DIR}/loader/entries/ostree-*.conf \
	| sed -e '/^aboot.*/d' \
	| sed -e '/^version .*/d' \
	| sed -e 's/^title/LABEL/g' \
	| sed -e 's/^linux/  KERNEL/g' \
	| sed -e 's/^options/  APPEND/g' \
	| sed -e 's/^initrd/  INITRD/g' >> ${SYSLINUX_CFG}
