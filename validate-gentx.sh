#!/bin/bash

set -x 

SGED_HOME="/tmp/sged$(date +%s)"
RANDOM_KEY="randomsgedvalidatorkey"
CHAIN_ID=sge-network-2
DENOM=usge
VALIDATOR_COINS=10000000000
GENTX_FILE=$(find ./$CHAIN_ID/gentxs -iname "*.json")
LEN_GENTX=$(echo ${#GENTX_FILE})
SGED_TAG="v0.0.5"

# Gentx Start date
start="2021-10-11 01:00:00Z"
# Compute the seconds since epoch for start date
stTime=$(date --date="$start" +%s)

# Gentx End date
end="2023-04-01 17:00:00Z"
# Compute the seconds since epoch for end date
endTime=$(date --date="$end" +%s)

# Current date
current=$(date +%Y-%m-%d\ %H:%M:%S)
# Compute the seconds since epoch for current date
curTime=$(date --date="$current" +%s)

if [[ $curTime < $stTime ]]; then
    echo "start=$stTime:curent=$curTime:endTime=$endTime"
    echo "Gentx submission is not open yet. Please close the PR and raise a new PR after 30-August-2021 10:00:00 UTC"
    exit 1
else
    if [[ $curTime > $endTime ]]; then
        echo "start=$stTime:curent=$curTime:endTime=$endTime"
        echo "Gentx submission is closed"
        exit 1
    else
        echo "Gentx is now open"
        echo "start=$stTime:curent=$curTime:endTime=$endTime"
    fi
fi

if [ $LEN_GENTX -eq 0 ]; then
    echo "No new gentx file found."
    exit 1
    
else
    set -e

    echo "GentxFiles::::"
    echo $GENTX_FILE


    # if command_exists go ; then
    #     echo "Golang is already installed"
    # else

    # sudo apt install -y git gcc make

    # sudo nano $HOME/.profile
    # # Add the following two lines at the end of the file
    # GOPATH=$HOME/go
    # PATH=$GOPATH/bin:$PATH
    # # Save the file and exit the editor
    # source $HOME/.profile
    # # Now you should be able to see your variables like this:
    # echo $GOPATH/home/ubuntu/go
    # echo $PATH/home/ubuntu/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin

    # go version
    # fi
    

    echo "...........Init Sged.............."

    git clone https://github.com/sge-network/sge
    cd sge
    git fetch --tags
    git checkout $SGED_TAG
    go mod tidy
    make install
    #chmod +x /usr/bin/sged

    sged keys add $RANDOM_KEY --keyring-backend test --home $SGED_HOME

    sged init --chain-id $CHAIN_ID validator --home $SGED_HOME

    echo "..........Fetching genesis......."
    rm -rf $SGED_HOME/config/genesis.json
    cp ../$CHAIN_ID/pre-genesis.json $SGED_HOME/config/genesis.json

    # this genesis time is different from original genesis time, just for validating gentx.
    sed -i '/genesis_time/c\   \"genesis_time\" : \"2021-09-02T16:00:00Z\",' $SGED_HOME/config/genesis.json

    find ../$CHAIN_ID/gentxs -iname "*.json" -print0 |
        while IFS= read -r -d '' line; do
            GENACC=$(cat $line | sed -n 's|.*"delegator_address":"\([^"]*\)".*|\1|p')
            denomquery=$(jq -r '.body.messages[0].value.denom' $line)
            amountquery=$(jq -r '.body.messages[0].value.amount' $line)

            echo $GENACC
            echo $amountquery
            echo $denomquery

            # only allow $DENOM tokens to be bonded
            if [ $denomquery != $DENOM ]; then
                echo "invalid denomination"
                exit 1
            fi

            # check the amount that can be bonded
            if [ $amountquery != $VALIDATOR_COINS ]; then
                echo "invalid amount of tokens"
                exit 1
            fi

            sged add-genesis-account $(jq -r '.body.messages[0].delegator_address' $line) $VALIDATOR_COINS$DENOM --home $SGED_HOME
        done

    mkdir -p $SGED_HOME/config/gentx/

    # add submitted gentxs
    cp -r ../$CHAIN_ID/gentxs/* $SGED_HOME/config/gentx/

    echo "..........Collecting gentxs......."
    sged collect-gentxs --home $SGED_HOME &> log.txt
    #sed -i '/persistent_peers =/c\persistent_peers = ""' $SGED_HOME/config/config.toml
    #sed -i '/minimum-gas-prices =/c\minimum-gas-prices = "0.25usge"' $SGED_HOME/config/app.toml

    sged validate-genesis --home $SGED_HOME

    echo "..........Starting node......."
    sged start --home $SGED_HOME &

    sleep 10s

    echo "...Сhecking network status.."

    sged status --node http://localhost:26657

    echo "...Cleaning the stuff..."
    killall sged >/dev/null 2>&1
    rm -rf $SGED_HOME >/dev/null 2>&1
fi
