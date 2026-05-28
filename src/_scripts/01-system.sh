#!/bin/bash
# System packages, timezone, locale, GUI support
set -euo pipefail

TZ_VAL=${TZ:-Asia/Shanghai}

chmod 777 /tmp

apt-get update
apt-get -y upgrade
apt-get -y install tzdata lsb-release wget software-properties-common gnupg locales

ln -snf /usr/share/zoneinfo/${TZ_VAL} /etc/localtime
echo ${TZ_VAL} > /etc/timezone
locale-gen en_US.UTF-8

apt-get -y install vim git curl zip unzip trash-cli parallel libssl-dev iputils-ping \
    build-essential ninja-build gdb systemd-coredump nfs-common cmake libopencv-dev \
    libgflags-dev libgoogle-glog-dev libgtest-dev libgmock-dev rsync git-lfs \
    tree tmux screen cloc acl man htop landscape-common ffmpeg \
    dbus-x11 fonts-wqy-zenhei fonts-noto-cjk mesa-utils libgl1-mesa-glx pulseaudio

rm -rf /var/lib/apt/lists/*
