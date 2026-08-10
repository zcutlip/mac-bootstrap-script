# Mac Boostrap Script TODO

## Issues from the last run

- Wireguard
    - no client installed
    - no client config made available on the system
    - impact: can't reach private git server to clone dotfiles
- 1Password
    - ~/.config/1Password/ssh/agent.toml needs to be set up
    - symlink for 1Password SSH socket
    - export SSH_AUTH_SOCK
    - impact: no SSH keys available to auth to private git server
