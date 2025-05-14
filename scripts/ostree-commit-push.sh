#!/bin/sh

OSTREE_REPO=repo
OSTREE_BRANCH=os/$(uname -m)/main
OSTREE_SERVER=localhost:2222
OSTREE_SERVER_USER=ostreejob
OSTREE_REMOTE_REPO_PATH=/home/${OSTREE_SERVER_USER}/repo
TARGET=target
PACKAGES=scripts/bootstrap.packages

usage="Usage: $(basename "$0") [OPTIONS]\n
Boostrap an Alpine root filesystem in \"./target\" directory. Then, make it as
an OSTree commit and push the commit to the OSTree repository server.\n
\n
Options:\n
\t-u, --user\tThe login user of the OSTree repository server.\n
\t\t\tDefault user is \"${OSTREE_SERVER_USER}\".\n
\t-s, --server\tThe IP, or server name (SSH port) of the OSTree repository server.\n
\t\t\tDefault server is \"${OSTREE_SERVER}\".\n
\t-b, --branch\tThe OSTree branch. Default branch is \"${OSTREE_BRANCH}\".\n
\t-h, --help\tshow this help text"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -u|--user)
      OSTREE_SERVER_USER="$2"
      shift 2  # Move past the option and its value
      ;;
    -s|--server)
      OSTREE_SERVER="$2"
      shift 2
      ;;
    -b|--branch)
      OSTREE_BRANCH="$2"
      shift 2
      ;;
    -h|--help)
      echo -e $usage
      exit 0
      ;;
    *)
      echo "Error: Unknown option: $1"
      echo -e $usage
      exit 1
      ;;
  esac
done

mkdir -p ${TARGET}

echo "Build filesystem to path: ${TARGET}"
./scripts/bootstrap.sh --root-target ${TARGET} --bootstrap-package-file ${PACKAGES}

echo "Add OSTree into initramfs"
grep ostree ${TARGET}/etc/mkinitfs/mkinitfs.conf
if [ $? -eq 1 ]; then
  sed -i 's/"$/ ide ostree"/' ${TARGET}/etc/mkinitfs/mkinitfs.conf
fi
# Use custom initramfs-init for preparing OSTree filesystem
install -D data/mkinitfs/initramfs-init ${TARGET}/usr/share/mkinitfs/initramfs-init

kver=$(ls ${TARGET}/lib/modules)
chroot ${TARGET} mkinitfs ${kver}

# Install and enable ostree-after-boot service
install -Dm755 data/etc/init.d/ostree-after-boot ${TARGET}/etc/init.d/ostree-after-boot
chroot ${TARGET} rc-update add ostree-after-boot boot

# Install and enable ostree-finalize-staged service into shutdown runlevel
install -Dm755 data/etc/init.d/ostree-finalize-staged ${TARGET}/etc/init.d/ostree-finalize-staged
install -Dm755 scripts/ostree-syslinux-cfg ${TARGET}/usr/bin/ostree-syslinux-cfg
chroot ${TARGET} rc-update add ostree-finalize-staged shutdown

echo "Tweak filesystem for OSTree deployment"
# Follow ostree's Deployments https://ostreedev.github.io/ostree/deployment/
config_file=$(ls ${TARGET}/boot/config-*)
KVER=${config_file#${TARGET}/boot/config-}
mv ${TARGET}/boot/vmlinuz-* ${TARGET}/lib/modules/${KVER}/vmlinuz
mv ${TARGET}/boot/initramfs-* ${TARGET}/lib/modules/${KVER}/initramfs.img
mv ${TARGET}/boot/* ${TARGET}/lib/modules/${KVER}/
mv ${TARGET}/etc ${TARGET}/usr/etc
rm -rf ${TARGET}/home
rm -rf ${TARGET}/root
rm -rf ${TARGET}/opt
rm -rf ${TARGET}/usr/local
rm -rf ${TARGET}/media
rm -rvf ${TARGET}/var
mkdir -p ${TARGET}/var
mkdir -p ${TARGET}/boot
mkdir -p ${TARGET}/sysroot
ln -s /sysroot/ostree ${TARGET}/ostree
ln -s /var/home ${TARGET}/home
ln -s /var/roothome ${TARGET}/root
ln -s /var/opt ${TARGET}/opt
ln -s /var/local ${TARGET}/usr/local
ln -s /run/media ${TARGET}/media
old_path=$(pwd)
cd ${TARGET}/usr/lib
ln -s ../../lib/modules modules
cd ${old_path}

echo "Commit the filesystem: ${TARGET} as an OSTree commit on branch ${OSTREE_BRANCH}"
BUILD_ID=$(date -u +"%Y%m%d_%H%M%S")
COMMIT_SUBJECT="Build ID: ${BUILD_ID}"
COMMIT_MSG="OSTree deployed filesystem on branch ${OSTREE_BRANCH}"
ostree --repo=${OSTREE_REPO} --mode=archive init
ostree --repo=${OSTREE_REPO} commit -s "${COMMIT_SUBJECT}" -m "${COMMIT_MSG}" --branch=${OSTREE_BRANCH} ${TARGET}

echo "Push the OSTree commit to repository: ${OSTREE_SERVER}/${OSTREE_REMOTE_REPO_PATH} on branch: ${OSTREE_BRANCH}"
ostree-push --repo=${OSTREE_REPO} ssh://${OSTREE_SERVER_USER}@${OSTREE_SERVER}/${OSTREE_REMOTE_REPO_PATH} ${OSTREE_BRANCH}
