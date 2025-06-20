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

## Setup Guide

### 1. Prerequisites

-   A modern terminal application like [iTerm2](https://iterm2.com/) (recommended for macOS).
-   [Homebrew](https://brew.sh/) for installing packages on macOS.

### 2. Installation

1.  **Install Oh My Zsh**
    If you don't already have Oh My Zsh installed, run the following command:
    ```bash
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    ```

2.  **Clone this Repository**
    Clone this repository to a location on your local machine (e.g., `~/.oh-my-zsh-config`).
    ```bash
    git clone https://github.com/your-username/oh-my-zsh-configuration.git ~/.oh-my-zsh-config
    ```

3.  **Backup and Link `.zshrc`**
    Backup your existing `.zshrc` and create a symbolic link to the one in this repository.
    ```bash
    mv ~/.zshrc ~/.zshrc.bak
    ln -s ~/.oh-my-zsh-config/.zshrc ~/.zshrc
    ```

4.  **Install Required Font**
    Powerlevel10k uses a special font to render icons. The recommended one is MesloLGS NF.
    ```bash
    brew install --cask font-meslo-lg-nerd-font
    ```

### 3. Configuration

1.  **Set Terminal Font**
    -   Open your terminal's preferences and select `MesloLGS NF` as your font.
    -   **For Terminal.app**: `Preferences` → `Profiles` → `Text` → `Font` → `Change...`.
    -   **For iTerm2**: `Preferences` (`⌘ + ,`) → `Profiles` → `Text` → `Font` → `Change...`.

2.  **Configure Powerlevel10k**
    -   The Powerlevel10k configuration wizard should start automatically. If not, run `p10k configure`.
    -   During the setup, when asked to choose a **"Prompt Connection"**, select **(3) No**. This disables the connecting lines between prompt segments and prevents a common resizing glitch.

3.  **Restart Zsh**
    -   For all changes to take effect, restart your terminal or run:
    ```bash
    exec zsh
    ```

## Known Issues

### Resizing Glitch

There is a known issue where resizing the terminal window horizontally can cause the prompt to misalign. This is largely mitigated by choosing not to have prompt connectors (`.`, `_`, or `/`) during the `p10k configure` setup.

## Uninstall

To revert to your previous configuration:

1.  **Remove the symbolic link:**
    ```bash
    rm ~/.zshrc
    ```
2.  **Restore your backup `.zshrc`:**
    ```bash
    mv ~/.zshrc.bak ~/.zshrc
    ```
3.  **(Optional) Remove the cloned repository:**
    ```bash
    rm -rf ~/.oh-my-zsh-config
    ```
4.  **Revert your terminal font** to your previous preference.
