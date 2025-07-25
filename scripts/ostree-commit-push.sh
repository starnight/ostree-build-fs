#!/bin/sh

OSTREE_REPO=repo
OSTREE_BRANCH=os/$(uname -m)/main
OSTREE_SERVER=localhost
SSH_PORT=2222
HTTP_PORT=8080
OSTREE_SERVER_USER=ostreejob
OSTREE_REMOTE_REPO_PATH=repo
OSTREE_REMOTE_REPO_FULL_PATH=/home/${OSTREE_SERVER_USER}/${OSTREE_REMOTE_REPO_PATH}
OSNAME=alpine
OSTREE_REMOTE_NAME=${OSNAME}
TARGET=target
PACKAGES=scripts/bootstrap.packages

usage="Usage: $(basename "$0") [OPTIONS]\n
Boostrap an Alpine root filesystem in \"./target\" directory. Then, make it as
an OSTree commit and push the commit to the OSTree repository server.\n
\n
Options:\n
\t-u, --user\tThe login user of the OSTree repository server.\n
\t\t\tDefault user is \"${OSTREE_SERVER_USER}\".\n
\t-s, --server\tThe IP, or server name of the OSTree repository server.\n
\t\t\tDefault server is \"${OSTREE_SERVER}\".\n
\t-sp, --ssh-port\tThe OSTree repository server's listening SSH port.\n
\t\t\tDefault SSH port is \"${SSH_PORT}\".\n
\t-hp, --http-port\tThe OSTree repository server's listening HTTP port.\n
\t\t\tDefault HTTP port is \"${HTTP_PORT}\".\n
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
    -sp|--ssh-port)
      SSH_PORT="$2"
      shift 2
      ;;
    -hp|--http-port)
      HTTP_PORT="$2"
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

# Link /(s)bin to /usr/(s)bin as workaround of
# https://gitlab.alpinelinux.org/alpine/aports/-/issues/16462
echo "Link /(s)bin to /usr/(s)bin"
mv ${TARGET}/bin/* ${TARGET}/usr/bin/
mv ${TARGET}/sbin/* ${TARGET}/usr/sbin/
rm -rf ${TARGET}/bin ${TARGET}/sbin
ln -s usr/bin ${TARGET}/bin
ln -s usr/sbin ${TARGET}/sbin
ln -sf /usr/bin/kmod ${TARGET}/sbin/depmod
ln -sf /usr/bin/kmod ${TARGET}/sbin/insmod
ln -sf /usr/bin/kmod ${TARGET}/sbin/lsmod
ln -sf /usr/bin/kmod ${TARGET}/sbin/modinfo
ln -sf /usr/bin/kmod ${TARGET}/sbin/modprobe
ln -sf /usr/bin/kmod ${TARGET}/sbin/rmmod

# Install and enable ostree-after-boot service
install -Dm755 data/etc/init.d/ostree-after-boot ${TARGET}/etc/init.d/ostree-after-boot
chroot ${TARGET} rc-update add ostree-after-boot boot

# Install and enable ostree-finalize-staged service into shutdown runlevel
install -Dm755 data/etc/init.d/ostree-finalize-staged ${TARGET}/etc/init.d/ostree-finalize-staged
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

OSTREE_SERVER_URL=http://${OSTREE_SERVER}:${HTTP_PORT}/${OSTREE_REMOTE_REPO_PATH}
echo "Pull commits on branch ${OSTREE_BRANCH} from OSTree repository server ${OSTREE_SERVER_URL}"
if ! [ -d "${OSTREE_REPO}" ]; then
  ostree --repo=${OSTREE_REPO} --mode=archive init
  ostree --repo="${OSTREE_REPO}" remote add ${OSTREE_REMOTE_NAME} ${OSTREE_SERVER_URL} ${OSTREE_BRANCH} --no-gpg-verify
fi
ostree --repo="${OSTREE_REPO}" pull ${OSTREE_REMOTE_NAME} ${OSTREE_BRANCH}

echo "Commit the filesystem: ${TARGET} as an OSTree commit on branch ${OSTREE_BRANCH}"
BUILD_ID=$(date -u +"%Y%m%d_%H%M%S")
COMMIT_SUBJECT="Build ID: ${BUILD_ID}"
COMMIT_MSG="OSTree deployed filesystem on branch ${OSTREE_BRANCH}"
ostree --repo=${OSTREE_REPO} commit -s "${COMMIT_SUBJECT}" -m "${COMMIT_MSG}" --branch=${OSTREE_BRANCH} ${TARGET}

echo "Push the OSTree commit to repository: ${OSTREE_SERVER}:${SSH_PORT}/${OSTREE_REMOTE_REPO_FULL_PATH} on branch: ${OSTREE_BRANCH}"
ostree-push --repo=${OSTREE_REPO} ssh://${OSTREE_SERVER_USER}@${OSTREE_SERVER}:${SSH_PORT}/${OSTREE_REMOTE_REPO_FULL_PATH} ${OSTREE_BRANCH}
