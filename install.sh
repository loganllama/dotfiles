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
    dest="$HOME/.config/$1"
    dest_dir="$(dirname $dest)"
    [ "$dest_dir" != "$HOME/.config" ] && rm -rf "$dest_dir"
    mkdir -p "$dest_dir"
    ln -s "$script_dir/$1" "$dest"
}

safe_obsidian_symlink() {
    if [ -z "$1" ]; then
        echo "Error: argument 1 is empty." >&2
        return 1
    fi
    if [ -z "$2" ]; then
        echo "Error: argument 2 is empty." >&2
        return 1
    fi
    script_dir=$(dirname "$(readlink -f "$0")")
    source_file="$script_dir/$1"
    dest_dir="/workspaces/obsidian"
    dest="$dest_dir/$2"
    echo "Creating symlink to $source_file in $dest"
    ln -s "$source_file" "$dest"
}

safe_home_symlink() {
    # if we proceed with an empty string, then we'd remove ~/
    if [ -z "$1" ]; then
        echo "Error: argument is empty." >&2
        return 1
    fi
    script_dir=$(dirname "$(readlink -f "$0")")
    echo "Creating symlink to $1 in home directory."
    rm -rf "$HOME/$1"
    ln -s "$script_dir/$1" "$HOME/$1"
}

# Create the ws1..ws9 jj workspaces used by parallel agent teams,
# each parked on the `parking_lot` bookmark. Idempotent: skips any
# workspace that is already registered with jj.
init_agent_jj_workspaces() {
    local obsidian_dir="/workspaces/obsidian"
    local ws_parent="/workspaces/obsidian-ws"

    if [ ! -d "$obsidian_dir" ]; then
        echo "Skipping jj workspace init: $obsidian_dir not found."
        return 0
    fi
    if ! command -v jj >/dev/null 2>&1; then
        echo "Skipping jj workspace init: jj not on PATH."
        return 0
    fi

    # Colocate jj with the existing git clone if not already done.
    if [ ! -d "$obsidian_dir/.jj" ]; then
        echo "Initializing jj (colocated) in $obsidian_dir..."
        (cd "$obsidian_dir" && jj git init --colocate) || {
            echo "jj git init failed; skipping workspace setup."
            return 0
        }
    fi

    # Track main against origin and align local main with main@origin so
    # subsequent operations (parking_lot creation, workspace placement,
    # and `jj sync`) are based on the upstream tip.
    (cd "$obsidian_dir" && jj bookmark track main --remote=origin) \
        || echo "Note: 'jj bookmark track main' skipped or already tracked."
    (cd "$obsidian_dir" && jj bookmark set main -r main@origin --allow-backwards) \
        || echo "Note: 'jj bookmark set main' skipped or already aligned."

    # The parking_lot bookmark is local-only — it doesn't exist in a
    # fresh clone. Create it (plus an empty commit on top of main to
    # anchor it) if missing, without disturbing the current working copy.
    local parking_desc="DND: workspace parking lot"
    if ! (cd "$obsidian_dir" && jj bookmark list parking_lot 2>/dev/null | grep -q '^parking_lot'); then
        echo "Creating parking_lot bookmark in $obsidian_dir..."
        if ! (cd "$obsidian_dir" && jj new main --no-edit -m "$parking_desc"); then
            echo "Failed to create parking_lot commit; skipping workspace setup."
            return 0
        fi
        # Note: `description()` matches the full description *including*
        # its trailing newline, so exact-matching with it never works for
        # non-empty descriptions. `subject()` matches the first line with
        # the newline stripped, which is what we want.
        if ! (cd "$obsidian_dir" && jj bookmark create parking_lot \
                -r "subject(exact:\"$parking_desc\") & empty()"); then
            echo "Failed to create parking_lot bookmark; skipping workspace setup."
            return 0
        fi
    fi

    mkdir -p "$ws_parent"

    for i in 1 2 3 4 5 6 7 8 9; do
        local ws_path="$ws_parent/ws$i"
        local ws_name="ws$i"

        if (cd "$obsidian_dir" && jj workspace list 2>/dev/null | grep -q "^$ws_name:"); then
            echo "jj workspace $ws_name already exists, skipping."
            continue
        fi

        echo "Creating jj workspace $ws_name at $ws_path..."
        if ! (cd "$obsidian_dir" && jj workspace add --name "$ws_name" "$ws_path"); then
            echo "Failed to create workspace $ws_name, continuing."
            continue
        fi
        # Park the new workspace on the parking_lot commit itself so
        # its working-copy revision shares the parking_lot change-id.
        (cd "$ws_path" && jj edit parking_lot) || \
            echo "Failed to park $ws_name on parking_lot."
    done

    # Rebase the user's mutable stacks onto main. Conflicts here are
    # normal and expected — the user resolves them as part of normal
    # work. (`jj sync` is an alias defined in jj/config.toml.)
    echo "Running 'jj sync' in $obsidian_dir..."
    (cd "$obsidian_dir" && jj sync) \
        || echo "Note: 'jj sync' reported issues (likely conflicts to resolve later)."
}

safe_dot_symlinks

safe_config_symlink "jj/config.toml"
safe_config_symlink "starship.toml"

safe_obsidian_symlink CLAUDE.local.md CLAUDE.local.md
safe_obsidian_symlink settings.local.json .claude/settings.local.json

safe_home_symlink "bash_additions.sh"
[ -f ~/bash_additions.sh ] && . ~/bash_additions.sh

# we do this before adding the bash_additions source to bashrc because fzf adds its own source to .bashrc
# which needs to happen before the bash_additions source so fzf will be in the path
# the above source was safe because we're not in an interactive session
# ... honestly we could probably omit the source in bash_additions now but meh
echo "Updating fzf..."
sudo apt remove -y fzf
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install --xdg --key-bindings --completion --update-rc

echo "Installing ~/bash_additions.sh..."
echo "[ -f ~/bash_additions.sh ] && . ~/bash_additions.sh" >> ~/.bashrc

echo "Installing Claude..."
curl -fsSL https://claude.ai/install.sh | bash

echo "Installing Starship..."
curl -sS https://starship.rs/install.sh | sh -s -- --yes

echo "Installing rustup..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
pathadd "$HOME/.cargo/bin"

echo "Installing Jujutsu..."
cargo install --locked --bin jj jj-cli
cargo install starship-jj --locked

# jj is now on PATH; provision the agent-team workspaces.
init_agent_jj_workspaces

echo "Installing DD Pup..."
curl -L https://github.com/DataDog/pup/releases/download/v0.60.0/pup_0.60.0_Linux_x86_64.tar.gz | tar xz && mv pup ~/bin/pup
