# FUSD Deployment Guide (Starknet Sepolia)

To ensure 100% functionality and a successful deployment to the Starknet Sepolia testnet, follow this guide.

## 📋 Prerequisites

1. **Install Scarb & Starknet Foundry**:
   - [Scarb v2.15.0](https://docs.swmansion.com/scarb/download.html)
   - [Starknet Foundry](https://foundry-rs.github.io/starknet-foundry/) (for `snforge` and `sncast`)
2. **Setup Wallet**:
   - Create a Braavos or Argent X wallet.
   - Switch to **Sepolia Testnet**.
   - Get Sepolia ETH from the [Starknet Faucet](https://faucet.starknet.io/).
3. **Install Starkli**:
   - Install the Starknet CLI tool: `curl https://get.starkli.sh | sh`.

## 🔬 Testing locally (Recommended)

Before deploying to testnet, run the integration tests using Starknet Foundry to simulate rebases and governance:

```bash
# Run integration tests
snforge test
```

## 🚀 Deployment Steps (using Starkli)

### 1. Declare Contract Classes
You must declare the classes before you can deploy instances.

```bash
# Declare FUSD Token
starkli declare target/dev/fusd_FUSDToken.contract_class.json --account <ACCOUNT_JSON> --keystore <KEYSTORE>

# Declare Monetary Policy
starkli declare target/dev/fusd_MonetaryPolicy.contract_class.json ...

# Repeat for Treasury, OracleAdapter, Staking, BondToken, BondAuction, Governor, Timelock
```

### 2. Deploy Contracts
The order is critical because of circular dependencies.

1. **Treasury & OracleAdapter**: No dependencies.
2. **FUSDToken**: Initial supply and owner (admin).
3. **Staking & BondToken**: Needs FUSD address.
4. **BondAuction**: Needs FUSD and BondToken.
5. **MonetaryPolicy**: Needs addresses of all the above.
6. **Timelock & Governor**: Governance hub.

### 3. Grant Roles (Initialization)
After deployment, you must link the contracts via AccessControl roles:

- **FUSDToken**: Grant `MINTER` and `BURNER` roles to the `MonetaryPolicy` and `BondAuction` addresses.
- **BondToken**: Grant `MINTER` role to `BondAuction` and `MonetaryPolicy`.
- **MonetaryPolicy**: Grant `ADMIN` role to the `Emergency` contract and the `Timelock`.

## 🧪 Post-Deployment Verification

1. **Initial Supply**: Verify you can see FUSD in your wallet.
2. **Oracle Sync**: Call `OracleAdapter::get_price` to ensure it's fetching data.
3. **Manual Rebase**: Once enough time has passed, call `MonetaryPolicy::rebase` and check for the `RebaseOperation` event.

## 🚨 Security Note
For a production environment, ensure that the **Timelock** is the only one with permission to call critical functions in `MonetaryPolicy` and `Treasury`.
