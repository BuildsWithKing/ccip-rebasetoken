# Cross-Chain Rebase Token

A cross-chain rebase token protocol built on Ethereum, enabling users to deposit assets into a vault and receive rebasing tokens that dynamically accrue interest over time. Powered by Chainlink CCIP for seamless cross-chain transfers.

## Overview

This project implements a **rebasing token** — an ERC-20 token whose `balanceOf` increases linearly over time without requiring explicit transfer events. Users deposit ETH (or any native token) into a Vault and receive Rebase Tokens (RBT) in return. Each user is assigned a personalized interest rate at the time of deposit, and the protocol's global interest rate can only decrease — rewarding early adopters with higher, locked-in rates.

Cross-chain functionality is enabled through [Chainlink CCIP](https://chain.link/ccip), allowing users to bridge their rebase tokens between supported chains (e.g., Ethereum Sepolia ↔ Arbitrum Sepolia ↔ zkSync Sepolia) while preserving their individual interest rates.

## Architecture

```
┌──────────────┐     deposit/redeem      ┌──────────────┐
│              │ ◄─────────────────────► │              │
│    Vault     │                         │ RebaseToken  │
│              │  mint/burn (onlyRole)   │   (ERC-20)   │
└──────────────┘                         └──────┬───────┘
                                                │
                                       lockOrBurn / releaseOrMint
                                                │
                                        ┌───────▼───────┐
                                        │RebaseTokenPool │
                                        │  (CCIP Pool)   │
                                        └───────┬───────┘
                                                │
                                          CCIP Router
                                                │
                                     ┌──────────┴──────────┐
                                     │  Remote Chain Pool   │
                                     │  (lockOrBurn /       │
                                     │   releaseOrMint)     │
                                     └─────────────────────┘
```

### Core Contracts

| Contract | Description |
|---|---|
| [`RebaseToken`](./src/RebaseToken.sol) | ERC-20 rebase token with per-user interest rates. Balances grow linearly over time. Interest rate can only decrease globally. |
| [`Vault`](./src/Vault.sol) | Accepts ETH deposits and mints RBT to users. Handles redemptions by burning RBT and returning ETH. |
| [`RebaseTokenPool`](./src/RebaseTokenPool.sol) | CCIP TokenPool implementation. Burns tokens on the source chain and mints on the destination, preserving the user's interest rate via `sourcePoolData`. |
| [`IRebaseToken`](./src/interfaces/IRebaseToken.sol) | Interface defining the RebaseToken external API used by the Vault and Pool contracts. |

### Key Mechanics

- **Linear Interest Accrual**: A user's balance grows as `principal × (1 + rate × time)`. Interest is materialized (minted) on every state-changing action (mint, burn, transfer, bridge).
- **Per-User Interest Rate**: Each user's rate is locked at deposit time based on the current global rate. The global rate can only decrease, so early depositors always retain a rate ≥ later depositors.
- **Cross-Chain Bridging**: When bridging via CCIP, the user's interest rate is encoded in the pool data and re-applied on the destination chain, ensuring continuity of rewards.

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)
- [Foundry-zksync](https://github.com/matter-labs/foundry-zksync) (for zkSync deployments)
- Node.js (for dependency management)

### Installation

```bash
# Clone the repository
git clone --recurse-submodules https://github.com/BuildsWithKing/ccip-rebase-token.git
cd ccip-rebase-token

# Install dependencies
forge install
npm install
```

### Build

```bash
forge build
```

### Test

```bash
# Run all tests (includes fork tests against Sepolia & Arbitrum Sepolia)
forge test

# Run with verbose output
forge test -vvv

# Run a specific test
forge test --match-test testDepositLinear -vvv
```

### Deploy

Deployment is handled through Foundry scripts in [`script/`](./script/):

| Script | Description |
|---|---|
| [`Deployer.s.sol`](./script/Deployer.s.sol) | Deploys `RebaseToken`, `RebaseTokenPool`, and `Vault` contracts. Sets up CCIP admin roles and pool registration. |
| [`ConfigurePool.s.sol`](./script/ConfigurePool.s.sol) | Configures rate limiters and remote chain pools for CCIP cross-chain messaging. |
| [`BridgeTokens.s.sol`](./script/BridgeTokens.s.sol) | Sends tokens across chains via CCIP. |

#### Local Testing (CCIPLocalSimulatorFork)

The test suite uses `CCIPLocalSimulatorFork` to simulate cross-chain messaging locally without needing live testnet contracts:

```bash
forge test --match-contract CrossChainTest -vvv
```

#### Live Testnet Deployment

1. Configure your RPC endpoints and wallet in `foundry.toml` or `.env`.
2. Deploy to Sepolia:

```bash
forge script script/Deployer.s.sol:TokenAndPoolDeployer \
  --rpc-url ${SEPOLIA_RPC_URL} \
  --account myaccount \
  --broadcast
```

3. Deploy the Vault:

```bash
forge script script/Deployer.s.sol:VaultDeployer \
  --rpc-url ${SEPOLIA_RPC_URL} \
  --account myaccount \
  --broadcast --sig "run(address)" <REBASE_TOKEN_ADDRESS>
```

4. Configure the pool for cross-chain:

```bash
forge script script/ConfigurePool.s.sol:ConfigurePool \
  --rpc-url ${SEPOLIA_RPC_URL} \
  --account myaccount \
  --broadcast \
  --sig "run(address,uint64,address,address,bool,uint128,uint128,bool,uint128,uint128)" \
  <LOCAL_POOL> <REMOTE_CHAIN_SELECTOR> <REMOTE_POOL> <REMOTE_TOKEN> \
  false 0 0 false 0 0
```

5. Bridge tokens:

```bash
forge script script/BridgeTokens.s.sol:BridgeTokensScript \
  --rpc-url ${SEPOLIA_RPC_URL} \
  --account myaccount \
  --broadcast \
  --sig "run(address,uint64,address,uint256,address,address)" \
  <RECEIVER> <DEST_CHAIN_SELECTOR> <TOKEN> <AMOUNT> <LINK_TOKEN> <ROUTER>
```

#### zkSync Deployment

A helper script [`bridgeToZksync.sh`](./bridgeToZksync.sh) is provided for deploying and bridging to zkSync Sepolia:

```bash
source .env
bash bridgeToZksync.sh
```

## Project Structure

```
.
├── src/
│   ├── RebaseToken.sol          # Core rebase token implementation
│   ├── RebaseTokenPool.sol      # CCIP token pool for cross-chain transfers
│   ├── Vault.sol                # Deposit/redeem vault
│   └── interfaces/
│       └── IRebaseToken.sol     # RebaseToken interface
├── test/
│   ├── RebaseTokenTest.t.sol    # Unit tests for RebaseToken & Vault
│   └── CrossChainTest.t.sol     # Cross-chain CCIP integration tests
├── script/
│   ├── Deployer.s.sol           # Deployment scripts
│   ├── ConfigurePool.s.sol      # Pool configuration script
│   └── BridgeTokens.s.sol       # Token bridging script
├── foundry.toml                 # Foundry configuration
├── bridgeToZksync.sh            # zkSync deployment helper
└── remappings.txt               # Solidity import remappings
```

## Dependencies

- [OpenZeppelin Contracts v5.3.0](https://github.com/OpenZeppelin/openzeppelin-contracts) — ERC-20, Ownable, AccessControl
- [Chainlink CCIP](https://github.com/smartcontractkit/chainlink-ccip) — Cross-chain messaging & token pools
- [Chainlink Local](https://github.com/smartcontractkit/chainlink-local) — Local CCIP simulator for testing
- [Forge Std](https://github.com/foundry-rs/forge-std) — Testing utilities

## License

This project is licensed under the [MIT License](./LICENSE).
