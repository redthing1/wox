
# building packages

build [pacur](https://github.com/pacur/pacur) container for target system, then, run the distro-specific pacur container to build packages.

## example: debian

go to somewhere you can clone pacur:
```sh
git clone https://github.com/pacur/pacur
cd pacur/docker
(export DISTRO=debian-bullseye && cd $DISTRO && podman build --rm . -t "pacur/$DISTRO")
```

then, go to this pkg dir and build packages:
```sh
podman run --rm -t -v `pwd`:/pacur pacur/debian-bullseye
```
