# ostree-build-fs

Build filesystem with OSTree

## Have OSTree Server Side Cluster

Use `podman` as the container tool, and `podman-compose` as the compose tool.
```shell
$ podman-compose -f docker/server-cluster.yaml up --remove-orphans
```
According to [docker/server-cluster.yaml](docker/server-cluster.yaml), the cluster has
* HTTP service listening on `8080` port
* sshd service listening on `2222` port

Note: Other container tools are available, too. For example, `docker` and `docker-compose`.

## Build a New OSTree Commit on a Client

1. Prepare the environment to build OSTree commit, including the tool `ostree-push` as a container image:
```shell
$ podman build -t localhost/source-client:latest . -f docker/source-client.Dockerfile
```
2. Run a container to build a new OSTree commit from the filesystem held by the local folder: `tree`, then `ostree-push` the OSTree commit to the OSTree Server side cluster:
```
$ podman run -it --rm --network host localhost/source-client:latest sh
# cd ~
# OSTREE_REPO=repo
# OSTREE_BRANCH=foo
# OSTREE_SERVER=localhost:2222
# OSTREE_SERVER_USER=ostreejob
# OSTREE_REMOTE_REPO_PATH=/home/${OSTREE_SERVER_USER}/repo
# mkdir tree
# echo "Hello world!!" > tree/hello.txt
# ostree --repo=${OSTREE_REPO} --mode=archive init
# ls
repo  tree
# ostree --repo=${OSTREE_REPO} commit -s "test commit" -m "test commit message body" --branch=${OSTREE_BRANCH} tree/
72ce24377da25acff4f3b28032a3babbbacd242a88909155ab7bcc04a2ab01fd
# ostree --repo=${OSTREE_REPO} log ${OSTREE_BRANCH}
commit 72ce24377da25acff4f3b28032a3babbbacd242a88909155ab7bcc04a2ab01fd
ContentChecksum:  9b67b15b625b62f6a20b2cff33c0effe77f4d7fd942ad6639b3c1e7f0f115f98
Date:  2025-03-16 13:37:36 +0000

    test commit

    test commit message body

# ostree-push --repo=${OSTREE_REPO} ssh://${OSTREE_SERVER_USER}@${OSTREE_SERVER}/${OSTREE_REMOTE_REPO_PATH} ${OSTREE_BRANCH}
INFO:otpush.push:Regenerating summary file
INFO:otpush.push:Serving /root/repo on http://127.0.0.1:36401 from process 8
The authenticity of host '[localhost]:2222 ([::1]:2222)' can't be established.
ED25519 key fingerprint is SHA256:XJEiiaPs3SEYMREiuOEagGE7GIKjEL2H38Hs6dnprRM.
This key is not known by any other names.
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added '[localhost]:2222' (ED25519) to the list of known hosts.
ostreejob@localhost's password:
INFO:otpush.push:Connected local HTTP port 36401 to remote port 42143
INFO:otpush.receive:Remote commits:
INFO:otpush.receive: foo 72ce24377da25acff4f3b28032a3babbbacd242a88909155ab7bcc04a2ab01fd
INFO:otpush.receive:Current commits:
INFO:otpush.receive: foo None
3 metadata, 1 content objects fetched; 592 B transferred in 0 seconds
INFO:otpush.receive:Updating repo metadata with ostree --repo=//home/ostreejob/repo summary --update
```
* `OSTREE_REPO` is the folder path holding the local OSTree repository.
* `OSTREE_BRANCH` is the OSTree branch.
* `OSTREE_REMOTE_REPO_PATH` is the folder path of the remote OSTree repository on the OSTree server side cluster.
* `tree` is the folder holding the source filesystem.

Note: To avoid type ssh user's password everytime, use `ssh-copy-id` to copy the public key to the sshd server. CI/CD may need this design. More details in [ssh-copy-id Command with Examples](https://linuxopsys.com/ssh-copy-id-command).

## Pull the OSTree Commit on Another Client

1. Create a local OSTree repository.
2. Add a remote OSTree repository address to the local OSTree repository.
3. Pull OSTree commits from the remote OSTree repository to the local OSTree repository.
4. Checkout the OSTree commit to the local folder: `local_tree` as the filesystem.

Here is the example:
```shell
$ podman run -it --rm --network host docker.io/library/alpine:latest sh
# apk add --no-cache ostree
# cd ~
# OSTREE_REPO=repo
# OSTREE_BRANCH=foo
# OSTREE_REMOTE_NAME=upstream
# OSTREE_SERVER_URL=http://localhost:8080/repo/
# ostree --repo=${OSTREE_REPO} --mode=archive init
# ls
repo
# ostree --repo=${OSTREE_REPO} --no-gpg-verify remote add ${OSTREE_REMOTE_NAME} ${OSTREE_SERVER_URL} ${OSTREE_BRANCH}
# cat ./${OSTREE_REPO}/config
[core]
repo_version=1
mode=archive-z2

[remote "upstream"]
url=http://localhost:8080/repo/
branches=foo;
gpg-verify=false
# ostree --repo=${OSTREE_REPO} pull ${OSTREE_REMOTE_NAME}
3 metadata, 1 content objects fetched; 410 B transferred in 0 seconds; 14 bytes content written
# ostree --repo=${OSTREE_REPO} ls ${OSTREE_BRANCH}
d00755 0 0      0 /
-00644 0 0     14 /hello.txt
# ostree --repo=${OSTREE_REPO} cat ${OSTREE_BRANCH} /hello.txt
Hello world!!
# ostree log --repo=${OSTREE_REPO} ${OSTREE_BRANCH}
commit 72ce24377da25acff4f3b28032a3babbbacd242a88909155ab7bcc04a2ab01fd
ContentChecksum:  9b67b15b625b62f6a20b2cff33c0effe77f4d7fd942ad6639b3c1e7f0f115f98
Date:  2025-03-16 13:37:36 +0000

    test commit

    test commit message body

# ostree checkout --repo=${OSTREE_REPO} 72ce24377da25acff4f3b28032a3babbbacd242a88909155ab7bcc04a2ab01fd ./local_tree
# ls
local_tree  repo
# ls -l local_tree
total 4
-rw-r--r--    1 root     root            14 Mar 16 13:43 hello.txt
# cat local_tree/hello.txt
Hello world!!
```

Note: If the OSTree commit has not been signed by a vailable GPG key, for example in development environment, then it will hit error: GPG verification enabled, but no signatures found: `GPG verification enabled, but no signatures found`.
```log
error: Commit cf57fe6522ccaf09c416c4a39a208e66980d8df41a3a45353668ed9653bc69b1: GPG verification enabled, but no signatures found (use gpg-verify=false in remote config to disable)
```
Adding paramter `--no-gpg-verify` to `ostree remote add` is a quick workaround. However, please sign the OSTree commit in production environment! You can consult [`ostree-commit`](https://ostreedev.github.io/ostree/man/ostree-commit.html) for more signing commit information.


## Reference

* [ostree-push](https://github.com/dbnicholson/ostree-push)
