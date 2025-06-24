#!/bin/bash
current_path=$(pwd)
source ~/.profile
ulimit -n 46384
# Check for go installation
if ! command -v go >/dev/null 2>&1; then
  echo "Go is not installed. Please install Go first."
  exit 1
fi
go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.5.0
# Get OS and version
OS="$(uname -s)"
ARCH="$(uname -m)"
if [ "$OS" != "Darwin" ]; then
  echo "This script only supports macOS (Darwin)."
  exit 1
fi
OS_VERSION=$(sw_vers -productVersion)
BUILD_VERSION=$(sw_vers -buildVersion)
echo "macOS version: $OS_VERSION (Build $BUILD_VERSION)"

# Check for supported macOS versions (14.x or 15.x)
MAJOR_VERSION=$(echo "$OS_VERSION" | cut -d. -f1)
if [ "$MAJOR_VERSION" != "14" ] && [ "$MAJOR_VERSION" != "15" ]; then
  echo "Only macOS 14 (Sonoma) and 15 are supported."
  exit 1
fi

# Define the binary and installation paths
BINARY="qubeticsd"
INSTALL_PATH="$HOME/go/bin/"
BUILD_PATH="$current_path/macos${MAJOR_VERSION}build/"

# Check if the build directory exists
if [ ! -d "$BUILD_PATH" ]; then
  echo "Build directory $BUILD_PATH does not exist. Please ensure it is created and contains the $BINARY binary."
  exit 1
fi

# Check if the binary exists in the build directory
if [ ! -f "$BUILD_PATH$BINARY" ]; then
  echo "Binary $BINARY not found in $BUILD_PATH. Please ensure it is present."
  exit 1
fi

# Check if the installation path exists
if [ -d "$INSTALL_PATH" ]; then
  sudo cp "$BUILD_PATH$BINARY" "$INSTALL_PATH" && sudo chmod +x "${INSTALL_PATH}${BINARY}"
  echo "$BINARY installed or updated successfully!"
else
  echo "Installation path $INSTALL_PATH does not exist. Please create it."
  exit 1
fi
#==========================================================================
# read -r MONIKER
KEYS="john"
CHAINID="qubetics_9030-1"
MONIKER="$1"
KEYRING="os"
KEYALGO="eth_secp256k1"
LOGLEVEL="info"
# Set dedicated home directory for the streakkd instance
HOMEDIR="$HOME/.tmp-qubeticsd"

# Path variables
CONFIG=$HOMEDIR/config/config.toml
APP_TOML=$HOMEDIR/config/app.toml
CLIENT=$HOMEDIR/config/client.toml
GENESIS=$HOMEDIR/config/genesis.json
TMP_GENESIS=$HOMEDIR/config/tmp_genesis.json

# used to exit on first error
set -e

# User prompt if an existing local node configuration is found.
if [ -d "$HOMEDIR" ]; then
  printf "\nAn existing folder at '%s' was found. You can choose to delete this folder and start a new local node with new keys from genesis. When declined, the existing local node is started. \n" "$HOMEDIR"
  echo "Overwrite the existing configuration and start a new local node? [y/n]"
  read -r overwrite
else
  overwrite="Y"
fi

# Setup local node if overwrite is set to Yes, otherwise skip setup
if [[ $overwrite == "y" || $overwrite == "Y" ]]; then
	# Remove the previous folder
	sudo rm -rf "$HOMEDIR"
  current_path=$(pwd)

  # Set client config
  qubeticsd config keyring-backend $KEYRING --home "$HOMEDIR"
  qubeticsd config chain-id $CHAINID --home "$HOMEDIR"
  echo "===========================Copy these keys with mnemonics and save it in safe place ==================================="
  qubeticsd keys add $KEYS --keyring-backend $KEYRING --algo $KEYALGO --home "$HOMEDIR"
  echo "========================================================================================================================"
  echo "========================================================================================================================"
  qubeticsd init $MONIKER -o --chain-id $CHAINID --home "$HOMEDIR"

  #changes status in app,config files
  sed -i '' 's/timeout_commit = "3s"/timeout_commit = "6s"/g' "$CONFIG"
  sed -i '' 's/seeds = ""/seeds = ""/g' "$CONFIG"
  sed -i '' 's/prometheus = false/prometheus = true/' "$CONFIG"
  sed -i '' 's/prometheus-retention-time  = "0"/prometheus-retention-time  = "1000000000000"/g' "$APP_TOML"
  sed -i '' 's/enabled = false/enabled = true/g' "$APP_TOML"
  sed -i '' 's/enable = false/enable = true/g' "$APP_TOML"
  sed -i '' 's/swagger = false/swagger = true/g' "$APP_TOML"
  sed -i '' 's/enabled-unsafe-cors = false/enabled-unsafe-cors = true/g' "$APP_TOML"
  sed -i '' 's/pruning-keep-recent = "0".tmp-qubeticsd/pruning-keep-recent = "100000"/g' "$APP_TOML"
  sed -i '' 's/pruning-interval = "0"/pruning-interval = "100"/g' "$APP_TOML"

  sed -i '' 's/localhost/0.0.0.0/g' "$APP_TOML"
  sed -i '' 's/localhost/0.0.0.0/g' "$CONFIG"
  sed -i '' 's/localhost/0.0.0.0/g' "$CLIENT"
  sed -i '' 's/127.0.0.1/0.0.0.0/g' "$APP_TOML"
  sed -i '' 's/127.0.0.1/0.0.0.0/g' "$CONFIG"
  sed -i '' 's/127.0.0.1/0.0.0.0/g' "$CLIENT"
  sed -i '' 's/\[\]/["*"]/g' "$CONFIG"
  sed -i '' 's/\["*",\]/["*"]/g' "$CONFIG"
  sed -i '' 's/127.0.0.1/0.0.0.0/g' "$CLIENT"

  # Don't enable Rosetta API by default
  grep -q -F '[rosetta]' "$APP_TOML" && sed -i '' '/\[rosetta\]/,/^\[/ s/enable = true/enable = false/' "$APP_TOML"
  # Don't enable memiavl by default
  grep -q -F '[memiavl]' "$APP_TOML" && sed -i '' '/\[memiavl\]/,/^\[/ s/enable = true/enable = false/' "$APP_TOML"
  # these are some of the node ids help to sync the node with p2p connections
  sed -i '' 's/persistent_peers \s*=\s* ""/persistent_peers = "ad8e2053470a347d87f5125d54fe04d86155f7c4@159.138.134.250:26656,1cb538b9950c4f3ce89848101e6698bbf68ad40c@150.40.237.123:26656,41f8e8b5479374a21e69be09911a0c0dc6f41b23@49.0.247.123:26656"/g' "$CONFIG"

  # remove the genesis file from binary
  rm -rf $HOMEDIR/config/genesis.json

  # paste the genesis file 
  cp $current_path/genesis.json $HOMEDIR/config

  cd $HOMEDIR/data

  # Run this to ensure everything worked and that the genesis file is setup correctly
  qubeticsd validate-genesis --home "$HOMEDIR"
  echo "export DAEMON_NAME=qubeticsd" >> ~/.profile
  echo "export DAEMON_HOME=\"$HOMEDIR\"" >> ~/.profile
  source ~/.profile
  echo $DAEMON_HOME
  echo $DAEMON_NAME
  cosmovisor init "${INSTALL_PATH}${BINARY}"

  ADDRESS=$(qubeticsd keys list --home $HOMEDIR --keyring-backend $KEYRING | grep "address" | cut -c12-)
  qubeticsd debug addr "$ADDRESS" --home "$HOMEDIR" --keyring-backend "$KEYRING"
  WALLETADDRESS=$(qubeticsd debug addr "$ADDRESS" --home "$HOMEDIR" --keyring-backend "$KEYRING" | grep "Address hex:" | awk '{print $3}')
  echo "========================================================================================================================"
  echo "Qubetics Eth Hex Address==== "$WALLETADDRESS
  echo "========================================================================================================================"
fi

#========================================================================================================================================================
# Define variables
PLIST_PATH="$HOME/Library/LaunchAgents/com.qubetics.myservice.plist"

# Create the plist content
PLIST_CONTENT="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple Computer//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key>
    <string>com.qubetics.myservice</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>source ~/.profile && ${INSTALL_PATH}cosmovisor run start --home ${HOMEDIR}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${HOME}/logfile.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/error.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${HOME}/go/bin</string>
        <key>DAEMON_NAME</key>
        <string>qubeticsd</string>
        <key>DAEMON_HOME</key>
        <string>${HOMEDIR}</string>
    </dict>
</dict>
</plist>"

# Write the plist content to a temporary file
echo "$PLIST_CONTENT" > /tmp/com.qubetics.myservice.plist

# Move the temporary file to the final location
sudo mv /tmp/com.qubetics.myservice.plist "$PLIST_PATH"

# Set the correct ownership and permissions
sudo chown $USER "$PLIST_PATH"
sudo chmod 644 "$PLIST_PATH"

# Unload if already loaded
launchctl unload "$PLIST_PATH" 2>/dev/null || true

# Load and start the launch agent
launchctl load "$PLIST_PATH"
launchctl start com.qubetics.myservice

# Check the logs
# echo "Checking service logs..."
# tail -f $HOME/logfile.log
