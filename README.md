# EscrowMarketplace 🛡️

A Foundry-based Solidity escrow marketplace where clients can fund freelance jobs with ERC20 tokens, freelancers can submit work, and payments are released only after client approval.

> Current status: core escrow workflow implemented with unit tests in progress. This project is not audited and is not production-ready yet.

## What is implemented so far ✅

- **ERC20-funded jobs** using OpenZeppelin `SafeERC20`.
- **Job creation with upfront escrow funding**: the client creates a job and transfers the full payment amount into the contract.
- **Freelancer assignment**: each job is created for a specific freelancer.
- **Job metadata support** through a `metadataURI`, suitable for IPFS or off-chain job details.
- **Work acceptance flow**: the assigned freelancer can accept a funded job and move it into progress.
- **Work submission flow**: freelancers can submit a `deliveryURI` before the deadline.
- **Client approval flow**: clients can approve submitted work and release payment.
- **Platform fee support** in basis points, with fees sent to a configured recipient.
- **Client cancellation flow**:
  - funded jobs can be cancelled by the client before the freelancer accepts;
  - in-progress jobs can be cancelled by the client after the deadline has passed.
- **Refund handling** for cancelled jobs.
- **Custom errors and events** for clearer failure handling and easier indexing.
- **Foundry tests** covering the main happy paths, access control, validation rules, events, fees, refunds, and deadline behavior.

## Contract overview

The main contract lives in:

```text
src/EscrowMarketplace.sol
```

### Job lifecycle

```text
Created/Funded → InProgress → Submitted → Completed
       │              │
       │              └── Cancelled after deadline by client
       └── Cancelled before acceptance by client
```

> Note: `createJob` currently creates and funds the job in one transaction, so new jobs are stored with `Funded` status immediately.

### Job data

Each job stores:

- client address
- freelancer address
- ERC20 token address
- escrowed amount
- deadline
- current status
- metadata URI
- delivery URI

## Main functions

| Function | Purpose |
| --- | --- |
| `createJob(...)` | Creates a job and transfers ERC20 funds into escrow. |
| `getJob(jobId)` | Returns the stored job data. |
| `acceptJob(jobId)` | Lets the assigned freelancer accept a funded job. |
| `submitWork(jobId, deliveryURI)` | Lets the freelancer submit work before the deadline. |
| `approveWork(jobId)` | Lets the client approve work and release payment minus platform fee. |
| `cancelJob(jobId)` | Lets the client cancel a funded job before it starts and receive a refund. |
| `cancelExpiredJob(jobId)` | Lets the client cancel an in-progress job after its deadline and receive a refund. |

## Tech stack 🧰

- [Solidity](https://soliditylang.org/) `^0.8.24`
- [Foundry](https://book.getfoundry.sh/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)
- Forge tests with a mock ERC20 token

## Project structure

```text
src/
  EscrowMarketplace.sol       # Main escrow marketplace contract

test/
  EscrowMarketplace.t.sol     # Unit tests for the marketplace workflow
  mocks/MockERC20.sol         # ERC20 test token

foundry.toml                  # Foundry configuration
remappings.txt                # Import remappings
```

## Getting started

Install dependencies if needed:

```shell
forge install
```

Run the test suite:

```shell
forge test
```

Format the code:

```shell
forge fmt
```

## Important notes ⚠️

- The contract is currently designed around ERC20 payments only.
- There is no dispute resolution mechanism implemented yet, even though `Disputed` exists in the status enum.
- There is no admin function yet to update platform fees or the fee recipient after deployment.
- The project has not been audited.
- Do not use this in production without a full security review.

## License

MIT
