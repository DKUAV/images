#!/bin/bash
# Install ROS2. Reads ROS_DISTRO (default: jazzy) and ROS_TARGET (default: ros-base).
set -euo pipefail

ROS_DISTRO_VAL=${ROS_DISTRO:-jazzy}
ROS_TARGET_VAL=${ROS_TARGET:-ros-base}

usage() {
    cat <<'EOF'
Usage: ros2.sh [--distro <name>] [--target <name>]

Options:
  --distro <name>  ROS distribution (default: ROS_DISTRO or jazzy)
  --target <name>  Installation target (default: ROS_TARGET or ros-base)
  -h, --help       Show this help
EOF
}

if ! PARSED=$(getopt -o h -l help,distro:,target: -n "$(basename "$0")" -- "$@"); then
    usage >&2
    exit 64
fi
eval set -- "$PARSED"
while true; do
    case "$1" in
        --distro) ROS_DISTRO_VAL="$2"; shift 2 ;;
        --target) ROS_TARGET_VAL="$2"; shift 2 ;;
        -h | --help) usage; exit 0 ;;
        --) shift; break ;;
    esac
done
if [ "$#" -ne 0 ]; then
    echo "ros2.sh: unexpected positional arguments: $*" >&2
    usage >&2
    exit 64
fi

# Register the ROS apt repository before installing the requested packages.

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
