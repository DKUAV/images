#!/bin/bash
# Developer shell setup: zsh, oh-my-zsh, neovim (NvChad), nvm, fzf, eza, starship, sheldon, zoxide.
# Must run as the target non-root user (USER directive before this RUN in the Dockerfile).
# Reads ROS_DISTRO (default: humble).
set -euo pipefail

ROS_DISTRO_VAL=${ROS_DISTRO:-humble}

# ─── Init Apt ─────────────────────────────────────────────────────────────────

sudo apt-get update

# ── zsh ───────────────────────────────────────────────────────────────────────

sudo apt-get -y install zsh
sudo chsh -s /bin/zsh "$(whoami)"

# ── oh-my-zsh ────────────────────────────────────────────────────────────────

sh -c "$(wget https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh -O -)" "" --unattended

git clone https://github.com/zsh-users/zsh-completions \
    "${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/plugins/zsh-completions"
git clone https://github.com/zsh-users/zsh-autosuggestions \
    "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
    "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"

sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="ys"/g' $HOME/.zshrc
sed -i 's/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-completions)/g' $HOME/.zshrc

# ── vimrc ────────────────────────────────────────────────────────────────────

git clone --depth=1 https://github.com/amix/vimrc.git $HOME/.vim_runtime
sh $HOME/.vim_runtime/install_awesome_vimrc.sh
echo 'set mouse-=a' >> $HOME/.vim_runtime/my_configs.vim

# ── misc shell config ─────────────────────────────────────────────────────────

# zsh configuration
cat >> $HOME/.zshrc << 'ZSH_EOF'

setopt no_nomatch # disable * match

# uv shell completions
eval "$(uv generate-shell-completion zsh)"
eval "$(uvx --generate-shell-completion zsh)"

ZSH_EOF

# bash color prompt
sed -i 's/#force_color_prompt=yes/force_color_prompt=yes/g' $HOME/.bashrc

# vscode-server
mkdir -p $HOME/.vscode-server/data/Machine

# tmux
echo 'set -g history-limit 1000000' >> $HOME/.tmux.conf
echo '' >> $HOME/.tmux.conf

# ── ROS2 aliases ─────────────────────────────────────────────────────────────

echo "alias load_ros=\"source /opt/ros/${ROS_DISTRO_VAL}/setup.zsh\"" >> $HOME/.zshrc
echo '' >> $HOME/.zshrc
echo "alias load_ros=\"source /opt/ros/${ROS_DISTRO_VAL}/setup.bash\"" >> $HOME/.bashrc
echo '' >> $HOME/.bashrc

# ── nvm + Node.js LTS ────────────────────────────────────────────────────────

export PROFILE=$HOME/.zshrc
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash

export NVM_DIR="$HOME/.nvm"
# nvm.sh uses unset variables internally; disable -u for the duration
set +u
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install --lts
nvm use --lts
npm install -g pnpm
set -u

# ── neovim (NvChad) ──────────────────────────────────────────────────────────

cd /tmp
ARCH=$(uname -m)
case $ARCH in
    x86_64)  NVIM_ARCH="x86_64" ;;
    aarch64) NVIM_ARCH="arm64" ;;
    *) echo "Unsupported architecture: $ARCH" && exit 1 ;;
esac

curl -LO "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${NVIM_ARCH}.tar.gz"
tar -xf "nvim-linux-${NVIM_ARCH}.tar.gz"
rm "nvim-linux-${NVIM_ARCH}.tar.gz"
sudo rsync -av --ignore-existing "nvim-linux-${NVIM_ARCH}/" /usr/local
rm -rf "nvim-linux-${NVIM_ARCH}"

git clone https://github.com/NvChad/starter $HOME/.config/nvim --depth 1

# disable mouse support
cat >> $HOME/.config/nvim/init.lua << 'MOUSE_EOF'

-- disable mouse support
vim.opt.mouse = ""

MOUSE_EOF

# add custom plugins
cat > $HOME/.config/nvim/lua/plugins/custom.lua << 'LUA'
return {
  {
    "ibhagwan/fzf-lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {},
  },
  {
    "fei6409/log-highlight.nvim",
    opts = {},
  },
}
LUA

nvim --headless "+Lazy! sync" +qa
nvim --headless "+Lazy load nvim-treesitter" "+TSInstallSync! lua vim vimdoc c cpp python javascript" +qa

# Mason LSP servers — MasonInstall is async; poll until all packages are installed
cat > /tmp/mason_install.lua << 'LUA'
local packages = {"lua-language-server", "stylua", "pyright", "clangd"}
vim.defer_fn(function()
    local registry = require("mason-registry")
    for _, name in ipairs(packages) do
        local ok, p = pcall(registry.get_package, name)
        if ok and not p:is_installed() then p:install() end
    end
    vim.wait(120000, function()
        for _, name in ipairs(packages) do
            local ok, p = pcall(registry.get_package, name)
            if not ok or not p:is_installed() then return false end
        end
        return true
    end, 2000)
    vim.cmd("qa!")
end, 5000)
LUA
nvim --headless -c "luafile /tmp/mason_install.lua"
rm /tmp/mason_install.lua

# ─── Fzf ──────────────────────────────────────────────────────────────────────

git clone --depth 1 https://github.com/junegunn/fzf.git $HOME/.fzf
$HOME/.fzf/install --all
cat >> $HOME/.zshrc << 'FZF_EOF'
export FZF_CTRL_T_OPTS="
  --walker-skip .git,node_modules,target
  --preview 'bat -n --color=always {}'
  --bind 'ctrl-/:change-preview-window(down|hidden|)'"

FZF_EOF

# ─── Ezh ──────────────────────────────────────────────────────────────────────

ARCH=$(uname -m)
case $ARCH in
    x86_64)  EZA_ARCH="x86_64-unknown-linux-gnu" ;;
    aarch64) EZA_ARCH="aarch64-unknown-linux-gnu" ;;
    *) echo "Unsupported architecture: $ARCH" && exit 1 ;;
esac
wget -c "https://github.com/eza-community/eza/releases/latest/download/eza_${EZA_ARCH}.tar.gz" -O - | tar xz
sudo chmod +x eza
sudo chown root:root eza
sudo mv eza /usr/local/bin/eza

# ─── Starship ─────────────────────────────────────────────────────────────────

curl -sS https://starship.rs/install.sh | POSIXLY_CORRECT=1 bash -s -- -y
starship preset catppuccin-powerline -o $HOME/.config/starship.toml

# ─── Sheldon ──────────────────────────────────────────────────────────────────

curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh \
    | bash -s -- --repo rossmacarthur/sheldon --to $HOME/.local/bin

echo y | $HOME/.local/bin/sheldon init --shell zsh

$HOME/.local/bin/sheldon add omz-lib \
    --github ohmyzsh/ohmyzsh \
    --dir lib \
    --use history.zsh key-bindings.zsh clipboard.zsh completion.zsh directories.zsh
$HOME/.local/bin/sheldon add omz-git \
    --github ohmyzsh/ohmyzsh \
    --dir plugins/git \
    --use git.plugin.zsh
$HOME/.local/bin/sheldon add zsh-autosuggestions \
    --github zsh-users/zsh-autosuggestions
$HOME/.local/bin/sheldon add zsh-completions \
    --github zsh-users/zsh-completions
$HOME/.local/bin/sheldon add zsh-syntax-highlighting \
    --github zsh-users/zsh-syntax-highlighting

$HOME/.local/bin/sheldon lock

# ─── Zoxide ───────────────────────────────────────────────────────────────────

curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh

# ─── Witr ─────────────────────────────────────────────────────────────────────

curl -fsSL https://raw.githubusercontent.com/pranshuparmar/witr/main/install.sh | bash

# ─── Atuin ────────────────────────────────────────────────────────────────────

curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh -s -- --non-interactive

# ─── Apt Cache Clean ──────────────────────────────────────────────────────────

sudo rm -rf /var/lib/apt/lists/*
