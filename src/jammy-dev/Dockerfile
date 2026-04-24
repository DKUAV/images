FROM mcr.microsoft.com/devcontainers/base:ubuntu22.04

# Ali mirror
RUN sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list

RUN chmod 777 /tmp
RUN apt update

# Avoid select timezone
ENV DEBIAN_FRONTEND=noninteractive
ENV LANGUAGE="en_US.UTF-8"
ENV LANG=en_US:zh_CN.UTF-8
ENV LC_ALL=C
ARG TZ=Asia/Shanghai
RUN apt -y install tzdata && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone \
    && apt -y install locales && locale-gen en_US.UTF-8 \
    && apt -y install lsb-release wget software-properties-common gnupg

# Update environment variables
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/usr/local/lib"

# ─── System ───────────────────────────────────────────────────────────────────

RUN apt -y install wget vim git curl zip unzip trash-cli parallel libssl-dev iputils-ping \
    && apt -y install build-essential ninja-build gdb systemd-coredump nfs-common cmake \
    && apt -y install libgflags-dev libgoogle-glog-dev libgtest-dev libgmock-dev rsync git-lfs

RUN apt -y install tree tmux screen cloc acl man htop landscape-common

# clang-format 21
RUN wget https://apt.llvm.org/llvm.sh \
    && chmod +x llvm.sh \
    && ./llvm.sh 21 \
    && rm llvm.sh

# python
RUN apt install -y python3.10 python3-setuptools \
    && curl -LsSf https://bootstrap.pypa.io/pip/get-pip.py | python3.10 \
    && pip3 config set global.index-url https://mirrors.aliyun.com/pypi/simple/ \
    && pip3 install setuptools pandas numpy ipython \
    && pip3 install pytest pytest-cov pytest-xdist pytest-html pytest-mock \
    && pip3 install pytest-randomly pytest-timeout filelock \
    && pip3 install pre-commit rich BeautifulSoup4 allure-pytest \
    && pip3 install plottable matplotlib opencv_python openpyxl jira python-gitlab \
    && pip3 install flake8 black ruff mypy delegator.py build \
    && pip3 install psycopg2-binary peewee python-calamine \
    && pip3 install loguru fastapi aiofiles "uvicorn[standard]" python-multipart "celery[redis]" \
    && pip3 install "pybind11[global]" \
    && curl -LsSf https://astral.sh/uv/install.sh | sh

# Zsh
RUN apt -y install zsh && chsh -s /bin/zsh

# ─── User ─────────────────────────────────────────────────────────────────────

ARG USERNAME=luciole
ARG USER_UID=1001
ARG USER_GID=$USER_UID

# Create the user
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && apt install -y sudo \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

USER $USERNAME
WORKDIR /home/$USERNAME

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
    && echo 'set -g history-limit 1000000' >> ~/.tmux.conf
# unzip document
# RUN yes "y" | unminimize

# neovim
WORKDIR /tmp
RUN curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz \
    && tar -xf nvim-linux-x86_64.tar.gz \
    && rm nvim-linux-x86_64.tar.gz \
    && sudo rsync -av --ignore-existing nvim-linux-x86_64/ /usr/local \
    && rm -rf nvim-linux-x86_64 \
    && git clone https://github.com/NvChad/starter ~/.config/nvim --depth 1 \
    && echo '' >> ~/.config/nvim/init.lua \
    && echo '-- disable mouse' >> ~/.config/nvim/init.lua \
    && echo 'vim.opt.mouse = ""' >> ~/.config/nvim/init.lua \
    && echo '' >> ~/.config/nvim/init.lua

# vim plug
RUN sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs \
       https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'

# bat
RUN sudo apt install -y bat \
    && sudo ln -sn batcat /usr/bin/bat

# fzf
RUN git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf \
    && ~/.fzf/install --all

# change back to user home
WORKDIR /home/$USERNAME
