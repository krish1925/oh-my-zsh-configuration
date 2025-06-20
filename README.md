# Oh My Zsh Configuration

This repository contains a personalized and optimized `.zshrc` configuration for Zsh using Oh My Zsh and the Powerlevel10k theme.

## Prerequisites

- A modern terminal application. [iTerm2](https://iterm2.com/) is recommended for macOS.
- [Homebrew](https://brew.sh/) for installing packages on macOS.

## Installation

1.  **Install Oh My Zsh**

    If you don't have Oh My Zsh installed, run the following command:

    ```bash
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    ```

2.  **Clone this Repository**

    Clone this repository to a location of your choice on your local machine.

    ```bash
    git clone https://github.com/your-username/oh-my-zsh-configuration.git ~/.oh-my-zsh-config
    ```

3.  **Backup and Link `.zshrc`**

    Backup your existing `.zshrc` if you have one, and then create a symbolic link to the `.zshrc` file in this repository.

    ```bash
    mv ~/.zshrc ~/.zshrc.bak
    ln -s ~/.oh-my-zsh-config/.zshrc ~/.zshrc
    ```

4.  **Install Required Font**

    Powerlevel10k requires a specific font to render all the symbols and icons correctly. The recommended font is MesloLGS NF.

    ```bash
    brew install --cask font-meslo-lg-nerd-font
    ```

## Configuration

1.  **Set Terminal Font**

    -   Open your terminal's preferences:
        -   **Terminal.app**: `Preferences` → `Profiles` → `Text` → `Font` → `Change...`.
        -   **iTerm2**: `Preferences` (`⌘ + ,`) → `Profiles` → `Text` → `Font` → `Change...`.
    -   Select `MesloLGS NF` as the font.

2.  **Configure Powerlevel10k**

    The first time you open a new terminal session, the Powerlevel10k configuration wizard should start automatically. If it doesn't, run it manually:

    ```bash
    p10k configure
    ```

    Follow the prompts from the configuration wizard. Pay close attention to the following setting to avoid a visual glitch when resizing the terminal window.

    -   **Prompt Connection**: When asked to choose a "Prompt Connection", select **(3) No**. This will disable the dotted or solid lines connecting segments of the prompt, which can cause rendering issues.

    ![P10k Configure Prompt Connection](https://user-images.githubusercontent.com/romkatv/powerlevel10k/master/config-wizard-prompt-connection.png)

    *Image credit: romkatv/powerlevel10k*

3.  **Restart Zsh**

    For all changes to take effect, restart your terminal or source the `.zshrc` file (restarting is safer).

    ```bash
    exec zsh
    ```

## Known Issues

### Resizing Glitch

There is a known issue where resizing the terminal window horizontally (especially making it narrower) can cause the prompt to glitch or misalign. By choosing **not** to have prompt connectors (`.`, `_`, or `/`) during the `p10k configure` setup, this issue is largely mitigated.

## Reverting Changes

To uninstall this configuration:

1.  Remove the symbolic link:

    ```bash
    rm ~/.zshrc
    ```

2.  Restore your backup `.zshrc` (if you had one):

    ```bash
    mv ~/.zshrc.bak ~/.zshrc
    ```

3.  (Optional) Remove the cloned repository:

    ```bash
    rm -rf ~/.oh-my-zsh-config
    ```

4.  Change your terminal font back to your previous preference.
