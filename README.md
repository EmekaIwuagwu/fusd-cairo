# FUSD Cairo Protocol

FUSD is an algorithmic stablecoin protocol implemented in Cairo for the Starknet ecosystem. It utilizes a multi-contract architecture to manage supply expansion and contraction, backed by decentralized governance and multi-source oracle price feeds.

## 🚀 Features

- **Algorithmic Rebase**: Automated expansion and contraction phases managed by `MonetaryPolicy`.
- **FUSD Token**: A SNIP-2 compatible stablecoin with gated mint/burn roles.
- **Protocol-Owned Liquidity**: `LiquidityManager` coordinates rebalancing and LP position management.
- **Incentivized Staking**: Earn inflationary rewards by staking FUSD during expansion phases.
- **Debt Markets**: `BondAuction` and `BondToken` allow users to exchange FUSD for discounted bonds during contraction.
- **Decentralized Governance**: `Governor` and `Timelock` contracts ensure all protocol changes are transparent and community-led.
- **Circuit Breaker**: `Emergency` contract allows for rapid pausing of protocol modules in critical scenarios.
- **Gas Abstraction**: `Paymaster` support for paying transaction fees in FUSD.

## 🛠 Tech Stack

- **Language**: Cairo 2.15.0 (2024_07 edition)
- **Framework**: Scarb
- **Dependencies**: OpenZeppelin Cairo Contracts v1.0.0

## 📦 Project Structure

```text
src/
├── contracts/
│   ├── core/              # FUSD, MonetaryPolicy, Staking, BondAuction
│   ├── governance/        # Governor, Timelock, Emergency
│   ├── infrastructure/    # OracleAdapter, LiquidityManager, Paymaster
│   ├── interfaces/        # Standardized protocol traits
│   └── libraries/         # AccessControl, ReentrancyGuard components
└── tests.cairo            # Unit tests
```

## 🚀 Getting Started

### Prerequisites

- [Scarb v2.15.0](https://docs.swmansion.com/scarb/download.html)
- [Starknet Foundry (optional for advanced testing)](https://foundry-rs.github.io/starknet-foundry/)

### Build

```bash
scarb build
```

### Test

```bash
scarb test
```

## ⚖️ License

This project is licensed under the MIT License.
