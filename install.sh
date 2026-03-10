#!/bin/bash

# "standard" install.sh to replicate what it does when install.sh is not present.
safe_dot_symlinks() {
    # Get the directory in which this script lives.
    script_dir=$(dirname "$(readlink -f "$0")")

    # Get a list of all files in this directory that start with a dot.
    files=$(find -maxdepth 1 -type f -name ".*")

    # Create a symbolic link to each file in the home directory.
    for file in $files; do
        name=$(basename $file)
        echo "Creating symlink to $name in home directory."
        rm -rf ~/$name
        ln -s $script_dir/$name ~/$name
    done
}

safe_config_symlink() {
    # if we proceed with an empty string, then we'd remove ~/.config
    if [ -z "$1" ]; then
        echo "Error: argument is empty." >&2
        return 1
    fi
    script_dir=$(dirname "$(readlink -f "$0")")
    echo "Creating symlink to $1 in ~/.config/..."
    dest="~/.config/$1"
    dest_dir="$(dirname $dest)"
    [ "$dest_dir" != "~/.config/" ] && rm -rf "$dest_dir"
    mkdir -p "$dest_dir"
    ln -s "$script_dir/$1" "$dest"
}

safe_home_symlink() {
    # if we proceed with an empty string, then we'd remove ~/
    if [ -z "$1" ]; then
        echo "Error: argument is empty." >&2
        return 1
    fi
    script_dir=$(dirname "$(readlink -f "$0")")
    echo "Creating symlink to $1 in home directory."
    rm -rf "~/$1"
    ln -s "$script_dir/$1" "~/$1"
}

safe_dot_symlinks
safe_config_symlink "jj/config.toml"
safe_config_symlink "starship.toml"
safe_home_symlink "bash_additions.sh"

echo "Installing ~/bash_additions.sh..."
echo "[ -f ~/bash_additions.sh ] && . ~/bash_additions.sh" >> ~/.bashrc
[ -f ~/bash_additions.sh ] && . ~/bash_additions.sh

echo "Installing Claude..."
curl -fsSL https://claude.ai/install.sh | bash

echo "Installing Starship..."
curl -sS https://starship.rs/install.sh | sh -s -- --yes

echo "Installing rustup..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
pathadd "$HOME/.cargo/bin"

echo "Installing Jujutsu..."
cargo install --locked --bin jj jj-cli