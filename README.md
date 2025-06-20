# Oh My Zsh Configuration

This repository contains a personalized and optimized `.zshrc` configuration for Zsh, featuring the Powerlevel10k theme for a sleek and informative prompt.

## Preview

<img width="565" alt="image" src="https://github.com/user-attachments/assets/53b4d020-f72b-40a0-a8ce-c76a306138c8" />
<img width="564" alt="image" src="https://github.com/user-attachments/assets/bdecd75f-81be-4aa3-898a-78fc0f444a29" />
<img width="768" alt="image" src="https://github.com/user-attachments/assets/f93ba5b1-e78c-425b-a2d8-87120e9e80ec" />
<img width="764" alt="image" src="https://github.com/user-attachments/assets/4f8a7dc6-d2f3-4e40-8738-c885469fa7bc" />

## Features

-   **Performance Optimized**: Blazing fast Zsh startup time with `POWERLEVEL9K_INSTANT_PROMPT`.
-   **Powerlevel10k Theme**: A highly customizable and fast theme.
-   **Rich Plugins**: Comes with a curated list of plugins for enhanced productivity:
    -   `git`, `docker`, `kubectl`, `pip`, `npm`: Essential tool integrations.
    -   `zsh-autosuggestions` & `zsh-syntax-highlighting`: Fish-like autosuggestions and syntax highlighting.
    -   `fzf`: A command-line fuzzy finder.
    -   `z`: Jump to your most used directories.
-   **Smart History**: Enhanced history with timestamps, deduplication, and sharing across sessions.
-   **Useful Aliases**: A rich set of aliases for common commands (`gs` for `git status -sb`, `..` for `cd ..`, etc.).
-   **Auto-Correction**: Automatically corrects typos in commands.

## Setup

1.  **Prerequisites**
    -   A modern terminal like [iTerm2](https://iterm2.com/).
    -   [Homebrew](https://brew.sh/) for package installation.

2.  **Installation**
    ```bash
    # Install Oh My Zsh
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

    # Clone this repository
    git clone https://github.com/your-username/oh-my-zsh-configuration.git ~/.oh-my-zsh-config

    # Backup and link .zshrc
    mv ~/.zshrc ~/.zshrc.bak
    ln -s ~/.oh-my-zsh-config/.zshrc ~/.zshrc

    # Install the required font
    brew install --cask font-meslo-lg-nerd-font
    ```

3.  **Configuration**
    -   **Set Terminal Font**: In your terminal's preferences, change the font to `MesloLGS NF`.
    -   **Powerlevel10k Wizard**: Run `p10k configure` in your terminal.
        -   **Resizing Glitch Fix**: When asked for "Prompt Connection", choose **(3) No** to avoid visual glitches when resizing the terminal.

4.  **Restart Zsh**
    ```bash
    exec zsh
    ```

## Uninstall

To revert the changes:

```bash
# Remove the symbolic link
rm ~/.zshrc

# Restore your old .zshrc
mv ~/.zshrc.bak ~/.zshrc

# (Optional) Remove the cloned repo
rm -rf ~/.oh-my-zsh-config
```
And change your terminal font back to your previous preference.
