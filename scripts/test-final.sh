#!/bin/bash
# Cleanup
rm -rf $HOME/.baby

KEY="test"
CHAINID="${CHAINID:-test-final-1}"
# check if CHAINID is not defined
if [ -z "$CHAINID" ];
then
    CHAINID="test-final-1"
fi
KEYRING="test"
MONIKER="localtestnet"
KEYALGO="secp256k1"
LOGLEVEL="info"

# retrieve all args
WILL_RECOVER=0
WILL_INSTALL=0
WILL_CONTINUE=0
INITIALIZE_ONLY=0
# $# is to check number of arguments
if [ $# -gt 0 ];
then
    # $@ is for getting list of arguments
    for arg in "$@"; do
        case $arg in
        --initialize)
            INITIALIZE_ONLY=1
            shift
            ;;
        --recover)
            WILL_RECOVER=1
            shift
            ;;
        --install)
            WILL_INSTALL=1
            shift
            ;;
        --continue)
            WILL_CONTINUE=1
            shift
            ;;
        *)
            printf >&2 "wrong argument somewhere"; exit 1;
            ;;
        esac
    done
fi

# continue running if everything is configured
if [ $WILL_CONTINUE -eq 1 ];
then
    # Start the node (remove the --pruning=nothing flag if historical queries are not needed)
    babyd start --pruning=nothing --log_level $LOGLEVEL --minimum-gas-prices=0.0001ufinal --p2p.laddr tcp://0.0.0.0:2204 --grpc.address 0.0.0.0:2282 --grpc-web.address 0.0.0.0:2283
    exit 1;
fi

# validate dependencies are installed
command -v jq > /dev/null 2>&1 || { echo >&2 "jq not installed. More info: https://stedolan.github.io/jq/download/"; exit 1; }
command -v toml > /dev/null 2>&1 || { echo >&2 "toml not installed. More info: https://github.com/mrijken/toml-cli"; exit 1; }

# install babyd if not exist
if [ $WILL_INSTALL -eq 0 ];
then 
    command -v babyd > /dev/null 2>&1 || { echo >&1 "installing babyd"; make install; }
else
    echo >&1 "installing babyd"
    rm -rf $HOME/.baby*
    rm client/.env
    rm scripts/mnemonic.txt
    make install
fi

babyd config keyring-backend $KEYRING
babyd config chain-id $CHAINID

# determine if user wants to recorver or create new
MNEMONIC=""
if [ $WILL_RECOVER -eq 0 ];
then
    MNEMONIC=$(babyd keys add $KEY --keyring-backend $KEYRING --algo $KEYALGO --output json | jq -r '.mnemonic')
else
    MNEMONIC=$(babyd keys add $KEY --keyring-backend $KEYRING --algo $KEYALGO --recover --output json | jq -r '.mnemonic')
fi

echo "MNEMONIC=$MNEMONIC" >> client/.env
echo "MNEMONIC for $(babyd keys show $KEY -a --keyring-backend $KEYRING) = $MNEMONIC" >> scripts/mnemonic.txt

echo >&1 "\n"

# init chain
babyd init $MONIKER --chain-id $CHAINID

# Change parameter token denominations to ufinal
cat $HOME/.baby/config/genesis.json | jq '.app_state["staking"]["params"]["bond_denom"]="ufinal"' > $HOME/.baby/config/tmp_genesis.json && mv $HOME/.baby/config/tmp_genesis.json $HOME/.baby/config/genesis.json
cat $HOME/.baby/config/genesis.json | jq '.app_state["crisis"]["constant_fee"]["denom"]="ufinal"' > $HOME/.baby/config/tmp_genesis.json && mv $HOME/.baby/config/tmp_genesis.json $HOME/.baby/config/genesis.json
cat $HOME/.baby/config/genesis.json | jq '.app_state["gov"]["deposit_params"]["min_deposit"][0]["denom"]="ufinal"' > $HOME/.baby/config/tmp_genesis.json && mv $HOME/.baby/config/tmp_genesis.json $HOME/.baby/config/genesis.json
cat $HOME/.baby/config/genesis.json | jq '.app_state["mint"]["params"]["mint_denom"]="ufinal"' > $HOME/.baby/config/tmp_genesis.json && mv $HOME/.baby/config/tmp_genesis.json $HOME/.baby/config/genesis.json

# Set gas limit in genesis
# cat $HOME/.baby/config/genesis.json | jq '.consensus_params["block"]["max_gas"]="10000000"' > $HOME/.baby/config/tmp_genesis.json && mv $HOME/.baby/config/tmp_genesis.json $HOME/.baby/config/genesis.json

# enable rest server and swagger
toml set --toml-path $HOME/.baby/config/app.toml api.swagger true
toml set --toml-path $HOME/.baby/config/app.toml api.enable true
toml set --toml-path $HOME/.baby/config/app.toml api.address tcp://0.0.0.0:2203
toml set --toml-path $HOME/.baby/config/client.toml node tcp://0.0.0.0:2202

# create more test key
MNEMONIC_1=$(babyd keys add test1 --keyring-backend $KEYRING --algo $KEYALGO --output json | jq -r '.mnemonic')
MNEMONIC_2=$(babyd keys add test2 --keyring-backend $KEYRING --algo $KEYALGO --output json | jq -r '.mnemonic')

TO_ADDRESS=$(babyd keys show test1 -a --keyring-backend $KEYRING)
TO_ADDRESS_2=$(babyd keys show test2 -a --keyring-backend $KEYRING)
echo "MNEMONIC_1 for $TO_ADDRESS = $MNEMONIC_1" >> scripts/mnemonic.txt
echo "MNEMONIC_2 for $TO_ADDRESS_2 = $MNEMONIC_2" >> scripts/mnemonic.txt
echo "TO_ADDRESS_1=$TO_ADDRESS" >> client/.env
echo "TO_ADDRESS_2=$TO_ADDRESS_2" >> client/.env

# Allocate genesis accounts (cosmos formatted addresses)
babyd add-genesis-account $KEY 10000000ufinal --keyring-backend $KEYRING
babyd add-genesis-account test1 100000000ufinal --keyring-backend $KEYRING
babyd add-genesis-account test2 1000000000ufinal --keyring-backend $KEYRING

# Sign genesis transaction
babyd gentx $KEY 1000000ufinal --keyring-backend $KEYRING --chain-id $CHAINID

# Collect genesis tx
babyd collect-gentxs

# Run this to ensure everything worked and that the genesis file is setup correctly
babyd validate-genesis

# if initialize only, exit
if [ $INITIALIZE_ONLY -eq 1 ];
then
    exit 0;
fi

# Start the node (remove the --pruning=nothing flag if historical queries are not needed)
babyd start --pruning=nothing --log_level $LOGLEVEL --minimum-gas-prices=0.0001ufinal --p2p.laddr tcp://0.0.0.0:2204 --rpc.laddr tcp://0.0.0.0:2202 --grpc.address 0.0.0.0:2282 --grpc-web.address 0.0.0.0:2283
