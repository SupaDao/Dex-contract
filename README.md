# SupaSwap 🦄🔁

**SupaSwap** is a modular, gas-efficient decentralized exchange (DEX) protocol built with [Foundry](https://book.getfoundry.sh), drawing inspiration from **Uniswap** and **OpenZeppelin**. It supports concentrated liquidity, custom swap routing, protocol fees, on-chain governance, and NFT-based liquidity positions.

> Built by [SupaDao](https://supadao.xyz) — empowering real-world commerce with Web3 infrastructure.

---

## 📦 Folder Structure

```
.
├── base/                  # Utility modules for multicall, payment, self-permit, etc.
├── core/                  # Core DEX logic (Pool, Factory, PoolDeployer)
│   ├── callback/          # Callback contracts for minting, swapping, flash
│   └── interfaces/        # Core interfaces and callback interfaces
├── governance/            # DAO control: timelock, protocol fee, emergency pause
├── interfaces/            # ERC interfaces and shared protocol interfaces
├── libraries/             # Math, encoding, tick logic, NFT rendering, etc.
├── mocks/                 # Mock contracts for testing (ERC20, WETH, callbacks)
├── periphery/             # Public interaction layer (Router, Quoter, NFT manager)
│   └── interfaces/        # Periphery interfaces
├── upgrade/               # Proxy contracts for upgradability
├── script/                # Deployment & automation scripts (Foundry)
├── test/                  # Unit and integration tests (Forge)
├── foundry.toml           # Foundry config
└── README.md              # This file
```

---

## ✨ Features

- 🧠 **Core AMM** with Uniswap V3-style tick math and swap logic
- 💧 **NFT-based liquidity positions** with `NonfungiblePositionManager`
- 🔁 **SwapRouter** with multi-hop, permit, and multicall support
- 📊 **Quoter** for off-chain price estimation
- 🔒 **Governance** modules: protocol fee control, emergency pause, timelock
- 🧩 Modular and extensible contract architecture
- 🔬 Developed and tested entirely with Foundry

---

## 🚀 Getting Started

### 1. Install Foundry

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### 2. Clone the Project

```bash
git clone https://github.com/your-org/supaswap.git
cd supaswap
```

### 3. Install Dependencies

```bash
forge install
```

### 4. Run Tests

```bash
forge test -vv
```

### 5. Deploy Contracts (Example)

Update deployment parameters in `script/Deploy.s.sol`:

```bash
forge script script/Deploy.s.sol --rpc-url <RPC_URL> --private-key <YOUR_PRIVATE_KEY> --broadcast
```

---

## 🧪 Test Coverage

This project includes mocks for:

- ERC20 tokens
- WETH9 (WMONMock)
- Swap and mint callbacks
- Callback target testing

Use `forge coverage` (via [forge-coverage](https://github.com/foundry-rs/foundry-coverage)) to generate detailed coverage reports.

---

## 📜 License

MIT License © 2025 [Apus Industries Limited](https://apusindustries.com)  
See [`LICENSE`](./LICENSE) for details.

> This project is influenced by Uniswap and OpenZeppelin. Where applicable, original license headers are preserved.

---

## 👏 Acknowledgements

- [Uniswap Labs](https://uniswap.org)
- [OpenZeppelin Contracts](https://openzeppelin.com/contracts/)
- [Foundry (by Paradigm)](https://book.getfoundry.sh/)

---

## 🏗 Built By

**Apus Industries Limited**  
Smart Infrastructure • Web3 Systems • E-Commerce • Digital Assets  
🇳🇬 Lagos, Nigeria  
🔗 [apusindustries.com](https://apusindustries.com)
