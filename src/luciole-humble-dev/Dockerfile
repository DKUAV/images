FROM mcr.microsoft.com/devcontainers/base:ubuntu22.04

# Ali mirror
RUN sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list

RUN chmod 777 /tmp
RUN apt-get update && apt-get -y upgrade && rm -rf /var/lib/apt/lists/*

# Avoid select timezone
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ARG TZ=Asia/Shanghai
RUN apt-get update && apt-get -y install tzdata && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone \
    && apt-get -y install locales && locale-gen en_US.UTF-8 \
    && apt-get -y install lsb-release wget software-properties-common gnupg \
    && rm -rf /var/lib/apt/lists/*

# Update environment variables
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/usr/local/lib"

# ─── System ───────────────────────────────────────────────────────────────────

RUN apt-get update && apt-get -y install wget vim git curl zip unzip trash-cli parallel libssl-dev iputils-ping \
    && apt-get -y install build-essential ninja-build gdb systemd-coredump nfs-common cmake \
    && apt-get -y install libgflags-dev libgoogle-glog-dev libgtest-dev libgmock-dev rsync git-lfs \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get -y install tree tmux screen cloc acl man htop landscape-common \
    && rm -rf /var/lib/apt/lists/*

# clang-format 21
RUN wget https://apt.llvm.org/llvm.sh \
    && chmod +x llvm.sh \
    && ./llvm.sh 21 \
    && rm llvm.sh

# python
RUN apt-get update && apt-get install -y python3.10 python3-setuptools \
    && curl -LsSf https://bootstrap.pypa.io/pip/get-pip.py | python3.10 \
    && pip3 config set global.index-url https://mirrors.aliyun.com/pypi/simple/ \
    && pip3 install setuptools pandas numpy ipython \
    && pip3 install pytest pytest-xdist pytest-html pytest-mock \
    && pip3 install pytest-randomly pytest-timeout coverage pytest-cov filelock \
    && pip3 install pre-commit rich BeautifulSoup4 allure-pytest \
    && pip3 install plottable matplotlib opencv_python openpyxl jira python-gitlab \
    && pip3 install flake8 black ruff mypy delegator.py build \
    && pip3 install psycopg2-binary peewee python-calamine \
    && pip3 install loguru fastapi aiofiles "uvicorn[standard]" python-multipart "celery[redis]" \
    && pip3 install "pybind11[global]" \
    && curl -LsSf https://astral.sh/uv/install.sh | sh \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 cache purge

# Supports GUI
RUN apt-get update && apt-get install -y \
    dbus-x11 \
    fonts-wqy-zenhei \
    fonts-noto-cjk \
    mesa-utils \
    libgl1-mesa-glx \
    pulseaudio \
    && rm -rf /var/lib/apt/lists/*
ENV QT_X11_NO_MITSHM=1

# ROS2
ARG ROS_DISTRO=humble
ARG ROS_TARGET=desktop
RUN apt-get update && apt-get -y install software-properties-common \
    && add-apt-repository universe \
    && apt-get update && apt-get install curl -y \
    && export ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F'"' '{print $4}') \
    && curl -L -o /tmp/ros2-apt-source.deb "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})_all.deb" \
    && sudo dpkg -i /tmp/ros2-apt-source.deb \
    && rm /tmp/ros2-apt-source.deb \
    && apt-get update \
    && apt-get -y install ros-${ROS_DISTRO}-${ROS_TARGET} \
    && apt-get -y install ros-dev-tools \
    && rm -rf /var/lib/apt/lists/*

# ─── User ─────────────────────────────────────────────────────────────────────

ARG USERNAME=luciole
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Create the user
# If the specified UID/GID is already occupied by an existing user/group, remove it first
RUN existing_user=$(getent passwd $USER_UID | cut -d: -f1); \
    if [ -n "$existing_user" ]; then \
        home_dir=$(getent passwd $USER_UID | cut -d: -f6); \
        userdel "$existing_user"; \
        rm -rf "$home_dir"; \
    fi \
    && existing_group=$(getent group $USER_GID | cut -d: -f1); \
    if [ -n "$existing_group" ]; then \
        groupdel "$existing_group"; \
    fi \
    && groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && apt-get update && apt-get install -y sudo \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME \
    && rm -rf /var/lib/apt/lists/*

# XDG runtime dir — normally created by systemd-logind on login; must be created
# manually in Docker containers so VS Code IPC sockets can be written here.
RUN mkdir -p /run/user/$USER_UID \
    && chown $USERNAME:$USERNAME /run/user/$USER_UID \
    && chmod 0700 /run/user/$USER_UID

ENV XDG_RUNTIME_DIR=/run/user/$USER_UID

USER $USERNAME
WORKDIR /home/$USERNAME

# Zsh
RUN sudo apt-get update && sudo apt-get -y install zsh && sudo chsh -s /bin/zsh $USERNAME \
    && sudo rm -rf /var/lib/apt/lists/*

# ohmyzsh and vimrc
RUN sh -c "$(wget https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh -O -)" "" --unattended \
    && git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions \
    && git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions \
    && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting \
    && sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="ys"/g' ~/.zshrc \
    && sed -i 's/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-completions)/g' ~/.zshrc \
    && git clone --depth=1 https://github.com/amix/vimrc.git ~/.vim_runtime \
    && sh ~/.vim_runtime/install_awesome_vimrc.sh \
    && echo 'set mouse-=a' >> ~/.vim_runtime/my_configs.vim \
    && echo '' >> ~/.zshrc \
    && echo 'setopt no_nomatch # disable * match' >> ~/.zshrc\
    && echo '' >> ~/.zshrc\
    && sed -i 's/#force_color_prompt=yes/force_color_prompt=yes/g' ~/.bashrc \
    && mkdir -p ~/.vscode-server/data/Machine \
    && echo 'set -g history-limit 1000000' >> ~/.tmux.conf \
    && echo '' >> ~/.tmux.conf

# ROS2 environment
RUN echo 'alias load_ros="source /opt/ros/humble/setup.zsh"' >> ~/.zshrc \
    && echo '' >> ~/.zshrc \
    && echo 'alias load_ros="source /opt/ros/humble/setup.bash"' >> ~/.bashrc \
    && echo '' >> ~/.bashrc

# neovim
WORKDIR /tmp
RUN ARCH=$(uname -m) && case $ARCH in \
      x86_64) NVIM_ARCH="x86_64" ;; \
      aarch64) NVIM_ARCH="arm64" ;; \
      *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac \
    && curl -LO "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${NVIM_ARCH}.tar.gz" \
    && tar -xf "nvim-linux-${NVIM_ARCH}.tar.gz" \
    && rm "nvim-linux-${NVIM_ARCH}.tar.gz" \
    && sudo rsync -av --ignore-existing "nvim-linux-${NVIM_ARCH}/" /usr/local \
    && rm -rf "nvim-linux-${NVIM_ARCH}" \
    && git clone https://github.com/NvChad/starter ~/.config/nvim --depth 1 \
    && echo '' >> ~/.config/nvim/init.lua \
    && echo '-- disable mouse' >> ~/.config/nvim/init.lua \
    && echo 'vim.opt.mouse = ""' >> ~/.config/nvim/init.lua \
    && echo '' >> ~/.config/nvim/init.lua

# vim plug
RUN sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs \
       https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'

# bat
RUN sudo apt-get update && sudo apt-get install -y bat \
    && sudo ln -sf /usr/bin/batcat /usr/local/bin/bat \
    && sudo rm -rf /var/lib/apt/lists/*

# fzf
RUN git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf \
    && ~/.fzf/install --all

# eza
RUN ARCH=$(uname -m) && case $ARCH in \
      x86_64) EZA_ARCH="x86_64-unknown-linux-gnu" ;; \
      aarch64) EZA_ARCH="aarch64-unknown-linux-gnu" ;; \
      *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac \
    && wget -c "https://github.com/eza-community/eza/releases/latest/download/eza_${EZA_ARCH}.tar.gz" -O - | tar xz \
    && sudo chmod +x eza \
    && sudo chown root:root eza \
    && sudo mv eza /usr/local/bin/eza

# change back to user home
WORKDIR /home/$USERNAME
