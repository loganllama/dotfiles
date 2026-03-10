#!/bin/bash

# "standard" install.sh to replicate what it does when install.sh is not present.
create_symlinks() {
    # Get the directory in which this script lives.
    script_dir=$(dirname "$(readlink -f "$0")")

    # Get a list of all files in this directory that start with a dot.
    files=$(find -maxdepth 1 -type f -name "$1")

    # Create a symbolic link to each file in the home directory.
    for file in $files; do
        name=$(basename $file)
        echo "Creating symlink to $name in home directory."
        rm -rf ~/$name
        ln -s $script_dir/$name ~/$name
    done
}

create_symlinks ".*"
create_symlinks "bash_additions.sh"

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