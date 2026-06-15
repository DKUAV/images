#!/bin/bash
# Install ROS2. Reads ROS_DISTRO (default: humble) and ROS_TARGET (default: desktop).
set -euo pipefail

ROS_DISTRO_VAL=${ROS_DISTRO:-humble}
ROS_TARGET_VAL=${ROS_TARGET:-desktop}

apt-get update
apt-get -y install software-properties-common curl
add-apt-repository universe
apt-get update

ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest \
    | grep -F "tag_name" | awk -F'"' '{print $4}')

curl -L -o /tmp/ros2-apt-source.deb \
    "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})_all.deb"
dpkg -i /tmp/ros2-apt-source.deb
rm /tmp/ros2-apt-source.deb

apt-get update
apt-get -y install ros-${ROS_DISTRO_VAL}-${ROS_TARGET_VAL}
apt-get -y install ros-dev-tools
rm -rf /var/lib/apt/lists/*
