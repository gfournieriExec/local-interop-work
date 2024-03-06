#!/bin/bash

# Define the folder name
FOLDER_NAME="hyperlane-interoperability-test"

# Check if the folder already exists
if [ -d "$FOLDER_NAME" ]; then
    echo "The folder '$FOLDER_NAME' already exists."
else
    # Create the folder
    mkdir "$FOLDER_NAME"
    echo "The folder '$FOLDER_NAME' has been created."
fi

# Navigate into the folder
cd "$FOLDER_NAME"

# Function to create a wallet and save to a file
create_wallet() {
    wallet_file="$1.json"
    cast wallet new -j > "$wallet_file"
    echo "Wallet created and saved to $wallet_file"
}

# Create wallets and save them in respective files
create_wallet "deployer"
create_wallet "relayer_anvil1"
create_wallet "relayer_anvil2"
create_wallet "validator"

# Start the first anvil instance on the default port (8545)
nohup anvil > anvil_default.log 2>&1 &

echo "Anvil started on the default port (8545). Output is logged to anvil_default.log."

# Start the second anvil instance on port 8555 with chain-id 31338
nohup anvil -p 8555 --chain-id 31338 > anvil_custom.log 2>&1 &

echo "Anvil started on port 8555 with chain-id 31338. Output is logged to anvil_custom.log."

# Display running anvil processes
echo "Current running Anvil instances:"
pgrep -a anvil

# 'pkill anvil' to stop all anvil processes.

# Array of JSON wallet filenames
wallet_files=("deployer.json" "relayer_anvil1.json" "relayer_anvil2.json" "validator.json")

# Loop through each wallet file
for wallet_file in "${wallet_files[@]}"; do
    echo "Processing $wallet_file..."

    # Extract the address from the JSON file
    address=$(jq -r '.[0].address' "$wallet_file")
    if [ -z "$address" ]; then
        echo "Address not found in $wallet_file"
        continue
    fi

    # Define the private key for the sender (adjust as necessary)
    sender_private_key="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

    # Define the amount to send (converting 1 ether to wei)
    amount=$(cast tw 1)

    # Send transaction on RPC port 8555
    cast send "$address" \
        --private-key "$sender_private_key" \
        --value "$amount" \
        --rpc-url http://127.0.0.1:8555

    echo "Sent transaction to $address on RPC port 8555."

    # Send transaction on RPC port 8545
    cast send "$address" \
        --private-key "$sender_private_key" \
        --value "$amount" \
        --rpc-url http://127.0.0.1:8545

    echo "Sent transaction to $address on RPC port 8545."
done

#!/bin/bash

# Step 1: Extract the validator address from validator.json
validator_address=$(jq -r '.[0].address' validator.json)
if [ -z "$validator_address" ]; then
    echo "Validator address not found in validator.json"
    exit 1
fi

# Step 2: Create localConfigChains.yml
cat >localConfigChains.yml <<EOL
anvil1:
  chainId: 31337
  domainId: 31337
  name: anvil1
  protocol: ethereum
  rpcUrls:
    - http: http://127.0.0.1:8545
  nativeToken:
    name: Ether
    symbol: ETH
    decimals: 18

anvil2:
  chainId: 31338
  domainId: 31338
  name: anvil2
  protocol: ethereum
  rpcUrls:
    - http: http://127.0.0.1:8555
EOL

echo "localConfigChains.yml has been created."

# Step 3: Create ism.yml with the validator address dynamically inserted
cat >ism.yml <<EOL
anvil1:
  type: defaultFallbackRoutingIsm
  owner: '${validator_address}'
  domains:
    anvil2:
      type: staticAggregationIsm
      modules:
        - type: messageIdMultisigIsm
          threshold: 1
          validators:
            - '${validator_address}'
        - type: merkleRootMultisigIsm
          threshold: 1
          validators:
            - '${validator_address}'
      threshold: 1

anvil2:
  type: domainRoutingIsm
  owner: '${validator_address}'
  domains:
    anvil1:
      type: staticAggregationIsm
      modules:
        - type: messageIdMultisigIsm
          threshold: 1
          validators:
            - '${validator_address}'
        - type: merkleRootMultisigIsm
          threshold: 1
          validators:
            - '${validator_address}'
      threshold: 1
EOL

echo "ism.yml has been created with validator address: $validator_address."

# Extract the deployer's private key from deployer.json
deployer_private_key=$(jq -r '.[0].private_key' deployer.json)
if [ -z "$deployer_private_key" ]; then
    echo "Deployer's private key not found in deployer.json"
    exit 1
fi

# Execute hyperlane deploy command with the extracted deployer private key
hyperlane deploy core --targets anvil1,anvil2 --chains ./localConfigChains.yml --ism ./ism.yml --key "$deployer_private_key"

echo "Hyperlane core deployment initiated with deployer's key."
