# ssh-server

Connect to Server SSH Script

This script allows you to connect to a server SSH using SSH Key file.

Before using this script to connect server SSH you have to create SSH Key and setup on both your machine and the server you want to connect, to know how to create SSH key and setup on server tabe a look into [this github gist](https://gist.github.com/mshannaq/9d17d5a94997318d967739ebc46f5a44).

## Usage

```
ssh-server user@hostname [port]
```

- `<user@hostname>`: Specify the username and hostname of the server you want to connect to. If no username is provided, it defaults to `root`.
- `[port]`: Optionally specify the port number for the SSH connection. If no port is provided, it defaults to `22`.


## Installation

On macOS:

```
cd ~
wget https://raw.githubusercontent.com/mshannaq/linux-tools/main/ssh-server/ssh-server
sudo cp ssh-server /usr/local/bin/ssh-server
sudo chmod +x /usr/local/bin/ssh-server
rm ~/ssh-server
```
make sure to edit `~/.zshrc` and make sure you add at the end of file if `/usr/local/bin/` not added into PATH before.

```
export PATH="/usr/local/bin:$PATH"
```



## Configuration

Before using the script, you need to define the SSH key file path in the configuration file `ssh-server.config`. Follow these steps:

1. Create a file named `ssh-server.config` in the `~/.ssh/` directory.
2. Define the SSH key file path in the configuration file:
```
SSH_KEY_FILE=/path/to/your/ssh/key
```

Ensure that the configuration file has the correct permissions (`600`).

# Public keys

Make sure you copy the public key into the server using the command `ssh-copy-id`

example:
```bash
ssh-copy-id -p <sshport> -i ~/.ssh/<keyfilename>.pub username@server
```

If you don't have ssh key you can generate a new key using `ssh-keygen` command.

## Examples of using ssh-server command

Connect to a server with the default username (`root`) and port (`22`):
```bash
ssh-server serverhostname
```

Connect to a server with a specified username (`sam`) and port (`8888`):

```bash
ssh-server sam@hostname 8888

```

For more information on how to generate an SSH key, visit [this link](https://gist.github.com/mshannaq/9d17d5a94997318d967739ebc46f5a44).
