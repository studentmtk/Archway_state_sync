#!/bin/bash


exists()
{
  command -v "$1" >/dev/null 2>&1
}
if exists curl; then
	echo ''
else
  sudo apt install curl -y < "/dev/null"
fi
bash_profile=$HOME/.bash_profile
if [ -f "$bash_profile" ]; then
    . $HOME/.bash_profile
fi

function setup_Vars {
	if [ ! $ARCHWAY_NODENAME ]; then
		read -p "Enter node name: " ARCHWAY_NODENAME
		echo 'export ARCHWAY_NODENAME='\"${ARCHWAY_NODENAME}\" >> $HOME/.bash_profile
	fi
	. $HOME/.bash_profile
	sleep 1
}

function install_Go {
	cd $HOME
	wget -O go1.17.1.linux-amd64.tar.gz https://golang.org/dl/go1.17.1.linux-amd64.tar.gz
	rm -rf /usr/local/go && tar -C /usr/local -xzf go1.17.1.linux-amd64.tar.gz && rm go1.17.1.linux-amd64.tar.gz
	echo 'export GOROOT=/usr/local/go' >> $HOME/.bash_profile
	echo 'export GOPATH=$HOME/go' >> $HOME/.bash_profile
	echo 'export GO111MODULE=on' >> $HOME/.bash_profile
	echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile && . $HOME/.bash_profile
	go version
}

function install_Deps {
	cd $HOME
	sudo apt update
	sudo apt install make clang pkg-config libssl-dev liblz4-tool build-essential git jq ncdu bsdmainutils htop net-tools lsof -y < "/dev/null"
}

function install_Software {
	git clone https://github.com/archway-network/archway
	cd archway
	git checkout v0.0.5
	make install
	archwayd init $ARCHWAY_MONIKER --chain-id torii-1
	wget -O /root/.archway/config/genesis.json https://raw.githubusercontent.com/archway-network/testnets/main/torii-1/genesis.json
}

function state_sync {
	systemctl stop archwayd
	archwayd unsafe-reset-all
	external_address=$(wget -qO- eth0.me)
	peers="e7cf503eb59e22157647462a551fc1f7658430a7@89.163.151.226:26656"
	sed -i.bak -e "s/^external_address *=.*/external_address = \"$external_address:26656\"/; s/^persistent_peers *=.*/persistent_peers = \"$peers\"/" $HOME/.archway/config/config.toml
	sed -i.bak -e "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0utorii\"/;" $HOME/.archway/config/app.toml

	SNAP="http://89.163.151.226:26657"
	LATEST_HEIGHT=$(curl -s $SNAP/block | jq -r .result.block.header.height)
	TRUST_HEIGHT=$((LATEST_HEIGHT - 100))
	TRUST_HASH=$(curl -s "$SNAP/block?height=$TRUST_HEIGHT" | jq -r .result.block_id.hash)

	sed -i.bak -E "s|^(enable[[:space:]]+=[[:space:]]+).*$|\1true| ; \
	s|^(rpc_servers[[:space:]]+=[[:space:]]+).*$|\1\"$SNAP,$SNAP\"| ; \
	s|^(trust_height[[:space:]]+=[[:space:]]+).*$|\1$TRUST_HEIGHT| ; \
	s|^(trust_hash[[:space:]]+=[[:space:]]+).*$|\1\"$TRUST_HASH\"|" $HOME/.archway/config/config.toml

	sudo systemctl start archwayd
	journalctl -u archwayd -f
}

function install_Service {

echo "[Unit]
Description=ARCHWAY Node
After=network.target
[Service]
User=$USER
Type=simple
ExecStart=$(which archwayd) start
Restart=on-failure
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target" > $HOME/archwayd.service
sudo mv $HOME/archwayd.service /etc/systemd/system
sudo tee <<EOF >/dev/null /etc/systemd/journald.conf
Storage=persistent
EOF
sudo systemctl restart systemd-journald
sudo systemctl daemon-reload
sudo systemctl enable archwayd
}

PS3='Please enter your choice (input your option number and press enter): '
options=("full installation on a new server" "state_sync" "Quit")
select opt in "${options[@]}"
do
    case $opt in
        "full installation on a new server")
            		sleep 1
			setup_Vars
			install_Go
			install_Deps
			install_Software
			install_Service
			state_sync
			break
            ;;
        "state_sync")
            		sleep 1
			state_sync
			break
            ;;
        "Quit")
            break
            ;;
        *) echo -e "\e[91minvalid option $REPLY\e[0m";;
    esac
done
