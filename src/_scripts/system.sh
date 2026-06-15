#!/bin/bash
# Minimal system bootstrap: apt upgrade, timezone, locale.
# Developer CLI tools are installed separately by dev-tools.sh, and GUI / WSLg
# deps by wslg.sh, to keep each layer's cache independent.
set -euo pipefail

TZ_VAL=${TZ:-Asia/Shanghai}

chmod 777 /tmp

apt-get update
apt-get -y upgrade
apt-get -y install tzdata lsb-release wget software-properties-common gnupg locales

ln -snf /usr/share/zoneinfo/${TZ_VAL} /etc/localtime
echo ${TZ_VAL} > /etc/timezone
locale-gen en_US.UTF-8

rm -rf /var/lib/apt/lists/*
