#!/usr/bin/env bash

set -e

if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" != "arch" ] && [[ " ${ID_LIKE[*]} " != *" arch "* ]]; then
        echo "❌ Error: This script is explicitly configured for Arch Linux or Arch-based distributions."
        exit 1
    fi
else
    echo "❌ Error: Cannot detect Linux distribution."
    exit 1
fi

if ! command -v fish &> /dev/null; then
    echo "Installing fish shell..."
    sudo pacman -Syu --noconfirm fish
fi

echo "Choose installation type:"
echo "1) User-specific (~/.config/fish)"
echo "2) System-wide (/etc/fish)"
read -rp "Enter choice [1-2]: " choice

if [ "$choice" -eq 2 ]; then
    TARGET_DIR="/etc/fish"
    USE_SUDO="sudo"
else
    TARGET_DIR="$HOME/.config/fish"
    USE_SUDO=""
fi

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "Fetching repository metadata..."
SHA=$(curl -s "https://api.github.com/repos/Chimed2/Tacklebox/commits/main" | grep -m 1 '"sha":' | sed -E 's/.*"sha": "([^"]+)".*/\1/')

echo "Downloading configuration..."
curl -sL "https://codeload.github.com/Chimed2/Tacklebox/tar.gz/$SHA" | tar -xz -C "$TEMP_DIR" --strip-components=1

$USE_SUDO mkdir -p "$TARGET_DIR/functions" "$TARGET_DIR/completions"

safe_copy() {
    local src="$1"
    local dest="$2"
    if [ -f "$src" ]; then
        if [ -e "$dest" ] && [ ! -L "$dest" ]; then
            $USE_SUDO mv "$dest" "${dest}.bak"
        fi
        $USE_SUDO cp "$src" "$dest"
    fi
}

safe_copy "$TEMP_DIR/arch/config.fish" "$TARGET_DIR/config.fish"
safe_copy "$TEMP_DIR/arch/fish_variables" "$TARGET_DIR/fish_variables"

if [ -d "$TEMP_DIR/arch/functions" ]; then
    for file in "$TEMP_DIR/arch/functions"/*.fish; do
        [ -e "$file" ] || continue
        safe_copy "$file" "$TARGET_DIR/functions/$(basename "$file")"
    done
fi

if [ -d "$TEMP_DIR/arch/completions" ]; then
    for file in "$TEMP_DIR/arch/completions"/*.fish; do
        [ -e "$file" ] || continue
        safe_copy "$file" "$TARGET_DIR/completions/$(basename "$file")"
    done
fi

UNINSTALLER_PATH="$TARGET_DIR/functions/tacklebox-evaporate.fish"

cat << EOF | $USE_SUDO tee "$UNINSTALLER_PATH" > /dev/null
function tacklebox-evaporate --description "Uninstall Tacklebox configuration and files"
    echo "Removing Tacklebox files..."
    
    set -l target_dir "$TARGET_DIR"
    
    set -l files_to_remove config.fish fish_variables functions/tacklebox-evaporate.fish
    if test -d "\$target_dir/arch/functions"
        for f in "$TEMP_DIR/arch/functions"/*.fish
            set files_to_remove \$files_to_remove functions/(basename \$f)
        end
    end
    if test -d "$TEMP_DIR/arch/completions"
        for f in "$TEMP_DIR/arch/completions"/*.fish
            set files_to_remove \$files_to_remove completions/(basename \$f)
        end
    end

    for file in \$files_to_remove
        if test -f "\$target_dir/\$file"
            if test "$choice" -eq 2
                sudo rm "\$target_dir/\$file"
            else
                rm "\$target_dir/\$file"
            end
        end
    end

    echo "Tacklebox configuration evaporated successfully."
    functions -e tacklebox-evaporate
end
EOF

echo "Installation complete!"
echo "note: consider starring the tacklebox repo on github, thanks for installing!"
