#!/bin/bash
# System packages, timezone, locale, GUI support
set -euo pipefail

TZ_VAL=${TZ:-Asia/Shanghai}

chmod 777 /tmp

apt-get update && apt-get -y upgrade && rm -rf /var/lib/apt/lists/*

apt-get update \
    && apt-get -y install tzdata \
    && ln -snf /usr/share/zoneinfo/${TZ_VAL} /etc/localtime \
    && echo ${TZ_VAL} > /etc/timezone \
    && apt-get -y install locales \
    && locale-gen en_US.UTF-8 \
    && apt-get -y install lsb-release wget software-properties-common gnupg \
    && rm -rf /var/lib/apt/lists/*

apt-get update \
    && apt-get -y install \
        wget vim git curl zip unzip trash-cli parallel libssl-dev iputils-ping \
        build-essential ninja-build gdb systemd-coredump nfs-common cmake libopencv-dev \
        libgflags-dev libgoogle-glog-dev libgtest-dev libgmock-dev rsync git-lfs \
    && rm -rf /var/lib/apt/lists/*

apt-get update \
    && apt-get -y install \
        tree tmux screen cloc acl man htop landscape-common \
    && rm -rf /var/lib/apt/lists/*

# GUI support (WSLg)
apt-get update \
    && apt-get install -y \
        dbus-x11 \
        fonts-wqy-zenhei \
        fonts-noto-cjk \
        mesa-utils \
        libgl1-mesa-glx \
        pulseaudio \
    && rm -rf /var/lib/apt/lists/*
