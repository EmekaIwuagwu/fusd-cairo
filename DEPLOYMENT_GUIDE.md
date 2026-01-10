# FUSD Deployment Guide (Starknet Sepolia)

This guide walks you through deploying the FUSD protocol to Starknet Sepolia using your **Braavos** wallet.

## 📋 Initial Setup

### 1. Install Tools
Install **Starkli**, the standard CLI for Starknet:
```powershell
curl https://get.starkli.sh | sh
starkup
```

### 2. Prepare Environment variables
Copy the example environment file:
```powershell
cp .env.example .env
```
Fill in your `STARKNET_RPC` in the `.env` file. You can use the public Blast API provided in the example or get a private one from Alchemy/Infura.

### 3. Link your Braavos Wallet
You need to export your **Private Key** from your Braavos wallet settings.

**Create your Keystore:**
```powershell
starkli signer keystore from-key ./keystore.json
# Enter the private key when prompted.
```

**Fetch your Account Descriptor:**
(Replace `YOUR_BRAAVOS_ADDRESS` with your actual wallet address)
```powershell
starkli account fetch YOUR_BRAAVOS_ADDRESS --output ./account.json --rpc https://starknet-sepolia.public.blastapi.io
```

---

## 🚀 Deployment Workflow

### 1. Build the Project
Ensure you have the latest binary artifacts:
```powershell
scarb build
```

### 2. Declare Contract Classes
Every contract code must be "declared" once on the network before it can be deployed.
```powershell
# Example: Declaring the FUSD Token
starkli declare target/dev/fusd_FUSDToken.contract_class.json --watch
```
*Note: If a contract has already been declared by someone else (same bytecode), this step will just return the Class Hash.*

### 3. Deploy Contract Instances
Deployment follows a specific order to link addresses correctly.

#### Step A: Deploy Treasury & Oracle
```powershell
# Deploy Treasury (needs 1 arg: Admin address)
starkli deploy <TREASURY_CLASS_HASH> YOUR_ADDRESS --watch

# Deploy OracleAdapter (needs 2 args: [o1, o2, o3], Admin)
starkli deploy <ORACLE_CLASS_HASH> 2 0x0... 0x0... YOUR_ADDRESS --watch
```

#### Step B: Deploy FUSD Token
```powershell
# Deploy FUSD (Initial supply, Recipient, Owner)
starkli deploy <FUSD_CLASS_HASH> 1000000000000000000 0 YOUR_ADDRESS YOUR_ADDRESS --watch
```

#### Step C: Deploy Monetary Policy
```powershell
# Deploy Policy (Detailed args in the code)
starkli deploy <POLICY_CLASS_HASH> <FUSD_ADDR> <ORACLE_ADDR> <TREASURY_ADDR> <LQ_ADDR> <STAKE_ADDR> <BOND_ADDR> <AUCTION_ADDR> YOUR_ADDRESS --watch
```

---

## 🧪 Post-Deployment roles
After deployment, your wallet owns all contracts. You **MUST** transfer permissions so the code can talk to each other:

1.  **Grant Minter to Policy**: Call `FUSDToken::grant_role` (Minter role = `'MINTER'`) to the `MonetaryPolicy` address.
2.  **Grant Burner to Auction**: Call `FUSDToken::grant_role` (Burner role = `'BURNER'`) to `BondAuction`.

You can do this via the [Starkscan](https://sepolia.starkscan.co/) or [Voyager](https://sepolia.voyager.online/) block explorers under the "Write Contract" tab after connecting your Braavos wallet.
