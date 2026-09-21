# Story Proof-of-Creativity Core

> [!WARNING]
> **This repository is deprecated.**
>
> The Story Proof-of-Creativity contracts in this repository are deprecated as of September 19, 2026. This repository no longer receives new features, bug fixes, or security patches.
>
> [IP Portal](https://portal.story.foundation/) and the related services shut down on **October 15, 2026**. After that date, these services stop working. Deployed contracts stay on chain, but no team supports them.
>
> Do not start new integrations with this codebase. If you use these contracts today, plan your migration before October 15, 2026.

[![Version](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fstoryprotocol%2Fprotocol-core-v1%2Fmain%2Fpackage.json&query=%24.version&label=latest%20version)](https://github.com/storyprotocol/protocol-core-v1/releases)
[![Documentation](https://img.shields.io/badge/docs-v1-006B54)](https://docs.story.foundation/docs/what-is-story)
[![Website](https://img.shields.io/badge/website-story-00A170)](https://story.foundation)
[![Discord](https://img.shields.io/badge/discord-join%20chat-5B5EA6)](https://discord.gg/storyprotocol)
[![Twitter Follow](https://img.shields.io/twitter/follow/storyprotocol?style=social)](https://twitter.com/storyprotocol)

Story Proof-of-Creativity protocol brings programmability to IP. It transforms IPs into networks that transcend mediums and platforms, unleashing global creativity and liquidity. Instead of static JPEGs that lack interactivity and composability with other assets, programmable IPs are dynamic and extensible: built to be built upon. Creators and applications can register their IP with Story, converting their static IP into programmable IP by declaring a set of on-chain rights that any program can read and write on.

## Documentation

> :book: For detailed documentation, visit the **[Story docs](https://docs.storyprotocol.xyz/)**

### Overview

A piece of Intellectual Property is represented as an [IP Asset](#ip-asset) and its associated [IP Account](#ip-account), a smart contract designed to serve as the core identity for each IP. We also have various [Modules](#modules) to add functionality to IP Assets, like creating derivatives of them, disputing IP, and automating revenue flow between them.

![Story Proof-of-Creativity Architecture](./assets/beta-architecture.png)

### IP Asset

When you want to bring an IP on-chain, you mint an ERC-721 NFT. This NFT represents **ownership** over your IP.

Then, you **register** the NFT in our protocol through the [IP Asset Registry](/concepts/registry/ip-asset-registry). This deploys an [IP Account](/concepts/ip-asset/ip-account), effectively creating an "IP Asset". The address of that contract is the identifier for the IP Asset (the `ipId`).

The underlying NFT can be traded/sold like any other NFT, and the new owner will own the IP Asset and all revenue associated with it.

### IP Account

IP Accounts are smart contracts that are tied to an IP Asset, and do two main things:

1. Store the associated IP Asset's data, such as the associated licenses and royalties created from the IP
2. Facilitates the utilization of this data by various modules. For example, licensing, revenue/royalty sharing, remixing, and other critical features are made possible due to the IP Account's programmability.

The address of the IP Account is the IP Asset's identifier (the `ipId`).

### Modules

Modules are customizable smart contracts that define and extend the functionality of IP Accounts. Modules empower developers to create functions and interactions for each IP to make IPs truly programmable.

We already have a few core modules:

1. Licensing Module: create parent <-> child relationships between IPs, enabling derivatives of IPs that are restricted by the agreements in the license terms (must give attribution, share 10% revenue, etc)
2. Royalty Module: automate revenue flow between IPs, abiding by the negotiated revenue sharing in license terms
3. Dispute Module: facilitates the disputing and flagging of IP
4. Grouping Module: allows for IPs to be grouped together
5. Metadata Module: manage and view metadata for IP Assets

### Registry

The various registries on our protocol function as a primary directory/storage for the global states of the protocol. Unlike IP Accounts, which manage the state of specific IPs, a registry oversees the broader states of the protocol.

### Programmable IP License (PIL)

The PIL is a real, off-chain legal contract that defines certain **License Terms** for how an IP Asset can be legally licensed. For example, how an IP Asset is commercialized, remixed, or attributed, and who is allowed to do that and under what conditions.

We have mapped these same terms on-chain so you can easily attach terms to your IP Asset for others to seamlessly and transparently license your IP.


## Audit Reports

Audit reports are available in the [./audits](./audits) directory.

## Periphery Contracts

For access to the periphery contracts, which simplify developer workflows, please visit the [protocol-periphery-v1](https://github.com/storyprotocol/protocol-periphery-v1) repository.

## Deployed Contracts

Story Proof-of-Creativity Core contracts are deployed natively on Story. The deployed contract addresses can be found in [deployment-1315.json](./deploy-out/deployment-1315.json) (Story Aeneid Testnet) and [deployment-1514.json](./deploy-out/deployment-1514.json) (Story Homer Mainnet).

## Interact with Codebase

### Requirements

Please install the following:

- [Foundry / Foundryup](https://github.com/gakonst/foundry)
- [Hardhat](https://hardhat.org/hardhat-runner/docs/getting-started#overview)

And you probably already have `make` installed... but if not [try looking here.](https://askubuntu.com/questions/161104/how-do-i-install-make) and [here for MacOS](https://stackoverflow.com/questions/1469994/using-make-on-os-x)

### Quickstart

```sh
yarn # this installs packages
make # this builds
```

### Verify Upgrade Storage Layout (before scripts or tests)

```sh
forge clean
forge compile --build-info
npx @openzeppelin/upgrades-core@^1.32.3 validate out/build-info 
```

### Helper script to write an upgradable contract with ERC7201

1. Edit `script/foundry/utils/upgrades/ERC7201Helper.s.sol`
2. Change `string constant CONTRACT_NAME = "<the contract name>";`
3. Run the script to generate boilerplate code for storage handling and the namespace hash:
   
```sh
forge script script/foundry/utils/upgrades/ERC7201Helper.s.sol 
```
4. The log output is the boilerplate code, copy and paste in your contract

### Testing

```
make test
```

### Coverage

```
make coverage
```
Open `index.html` in `coverage/` folder.


### Working with a local network

Foundry comes with local network [anvil](https://book.getfoundry.sh/anvil/index.html) baked in, and allows us to deploy to our local network for quick testing locally.

To start a local network run:

```
make anvil
```

This will spin up a local blockchain with a determined private key, so you can use the same private key each time.

### Code Style
We employed solhint to check code style.
To check code style with solhint run:
```
make lint
```
To re-format code with prettier run:
```
make format
```

## Guidelines

[See our contribution guidelines](./GUIDELINES.md)


## Security

We welcome responsible disclosure of vulnerabilities. Please see our [security policy](SECURITY.md) for more information.

## Licensing

The license for Story Proof-of-Creativity Core is the Business Source License 1.1 (BUSL-1.1), see LICENSE.

After you have integrated our SDK and/or API with your application, in the Terms of Service for your application with your end users (which govern your end users' use of and access to your application), you must include the following sentence:

"This application is integrated with functionality provided by Story Protocol, Inc. that enables intellectual property registration and tracking. You acknowledge and agree that such functionality and your use of this application is subject to Story Protocol, Inc.'s End User Terms, which are available here: [https://www.storyprotocol.xyz/end-user-terms](https://www.storyprotocol.xyz/end-user-terms)."

## Document Generation

We use [solidity-docgen](https://github.com/OpenZeppelin/solidity-docgen) to generate the documents for smart contracts. Documents can be generated with the following command:

```
npx hardhat docgen
```

By default, the documents are generated in Markdown format in the `doc` folder of the project. Each Solidity file (`*.sol`) has its own Markdown (`*.md`) file. To update the configuration for document generation, you can update the following section in `hardhat.config.js`:

```
docgen: {
  outputDir: "./docs",
  pages: "files"
}
```

You can refer to the [config.ts](https://github.com/OpenZeppelin/solidity-docgen/blob/master/src/config.ts) of solidity-docgen for the full list of configurable parameters.


