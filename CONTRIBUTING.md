# Contributing to SupaSwap 🧑‍💻

First off, thank you for considering contributing to **SupaSwap**! 🎉  
This guide will help you get started with development, propose changes, report issues, or submit pull requests.

---

## 🚀 Getting Started

1. **Fork** the repository.
2. **Clone** your fork locally:

```bash
git clone https://github.com/SupaDao/Dex-contrac.git
cd Dex-contrac
```

3. **Install Foundry** if you haven’t:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

4. **Install dependencies**:

```bash
forge install
```

5. **Create a new branch** for your contribution:

```bash
git checkout -b feature/your-feature-name
```

---

## ✅ Contribution Types

You can contribute in many ways:

- ✨ New Features (e.g. new router logic, fee models)
- 🐛 Bug Fixes (logic bugs, off-by-one errors, etc.)
- 🧪 Test Improvements
- 🧱 Documentation updates (README, comments, inline docs)
- 🛠 Governance tooling and automation scripts

---

## 🔍 Coding Standards

- Write clear, readable, and gas-efficient Solidity.
- Use `forge fmt` to auto-format your code.
- Add appropriate NatSpec comments to all public/external functions.
- Structure new modules or interfaces consistently with the current architecture.

---

## 🧪 Running Tests

Before submitting a PR, make sure your changes pass all tests:

```bash
forge test -vv
```

Add new tests in the `test/` directory as needed. Use mocks if necessary.

---

## 📦 Committing and PRs

- Follow conventional commit messages:  
  `feat: add liquidity locking mechanism`  
  `fix: correct overflow in SwapMath`
- Ensure your PR has a clear title and description.
- Reference related issues in the PR description if applicable.

---

## 💬 Issues and Discussions

- For bugs or suggestions, open an [issue](https://github.com/your-org/supaswap/issues).
- For feature ideas, open a discussion or start a draft PR.

---

## 🙌 Code of Conduct

Be respectful, constructive, and helpful. We’re all building the future together 🌍

---

## 🧠 Credits

Inspired by [Uniswap](https://uniswap.org), [OpenZeppelin](https://openzeppelin.com), and the amazing Ethereum developer community 💜

---

Thank you for contributing to **SupaSwap**!

— [Apus Industries Limited](https://apusindustries.com)
