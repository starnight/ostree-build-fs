#!/bin/sh

OSTREE_REPO=repo
OSTREE_BRANCH=foo
OSTREE_SERVER=localhost:2222
OSTREE_SERVER_USER=ostreejob
OSTREE_REMOTE_REPO_PATH=/home/${OSTREE_SERVER_USER}/repo

echo "Build filesystem to path: ${TARGET}"
./scripts/bootstrap.sh ${TARGET}

echo "Tweak filesystem for OSTree deployment"
# Follow ostree's Deployments https://ostreedev.github.io/ostree/deployment/
config_file=$(ls ${TARGET}/boot/config-*)
KVER=${config_file#${TARGET}/boot/config-}
mv ${TARGET}/boot/vmlinuz-* ${TARGET}/lib/modules/${KVER}/vmlinuz
mv ${TARGET}/boot/initramfs-* ${TARGET}/lib/modules/${KVER}/initramfs.img
mv ${TARGET}/boot/* ${TARGET}/lib/modules/${KVER}/
mv ${TARGET}/etc ${TARGET}/usr/etc
rm -rvf ${TARGET}/var
mkdir ${TARGET}/var
old_path=$(pwd)
cd ${TARGET}/usr/lib
ln -s ../../lib/modules modules
cd ${old_path}

echo "Commit the filesystem as an OSTree commit and push it to the server"
BUILD_ID=$(date -u +"%Y%m%d_%H%M%S")
COMMIT_SUBJECT="Build ID: ${BUILD_ID}"
COMMIT_MSG="OSTree deployed filesystem on branch ${OSTREE_BRANCH}"

echo ${OSTREE_REPO}
echo ${TARGET}
echo ${OSTREE_BRANCH}

ostree --repo=${OSTREE_REPO} --mode=archive init
ostree --repo=${OSTREE_REPO} commit -s "${COMMIT_SUBJECT}" -m "${COMMIT_MSG}" --branch=${OSTREE_BRANCH} ${TARGET}
ostree-push --repo=${OSTREE_REPO} ssh://${OSTREE_SERVER_USER}@${OSTREE_SERVER}/${OSTREE_REMOTE_REPO_PATH} ${OSTREE_BRANCH}
