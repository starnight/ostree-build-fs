#!/bin/sh

TARGET=./target/
OSNAME=alpine
REPOPATH=${TARGET}/ostree/repo
OSTREE_BRANCH=foo
OSTREE_REMOTE_NAME=${OSNAME}
OSTREE_SERVER_URL=http://localhost:8080/repo/

ostree admin init-fs "${TARGET}"
ostree admin --sysroot="${TARGET}" os-init ${OSNAME}
ostree --repo=${REPOPATH} remote add ${OSTREE_REMOTE_NAME} ${OSTREE_SERVER_URL} ${OSTREE_BRANCH} --no-gpg-verify
ostree --repo="${REPOPATH}" pull ${OSTREE_REMOTE_NAME} ${OSTREE_BRANCH}
ostree admin deploy --sysroot=${TARGET} --os=${OSNAME} ${OSTREE_REMOTE_NAME}:${OSTREE_BRANCH}
