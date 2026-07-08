# EscrowMarketplace 🛡️

A Foundry-based Solidity escrow marketplace where clients can fund freelance jobs with ERC20 tokens, freelancers can submit work, and payments are released after client approval or arbitrator dispute resolution.

> Current status: core escrow workflow implemented with unit tests in progress. This project is not audited and is not production-ready yet.

## What is implemented so far ✅

- **ERC20-funded jobs** using OpenZeppelin `SafeERC20`.
- **Job creation with upfront escrow funding**: the client creates a job and transfers the full payment amount into the contract.
- **Freelancer assignment**: each job is created for a specific freelancer.
- **Job metadata support** through a `metadataURI`, suitable for IPFS or off-chain job details.
- **Work acceptance flow**: the assigned freelancer can accept a funded job and move it into progress.
- **Work submission flow**: freelancers can submit a `deliveryURI` before the deadline.
- **Client approval flow**: clients can approve submitted work and release payment.
- **Dispute opening flow**: the client or freelancer can move an in-progress or submitted job into `Disputed` status with a `disputeReasonURI`.
- **Dispute resolution flow**: a configured arbitrator can resolve disputed jobs by splitting the escrowed amount between client and freelancer.
- **Platform fee support** in basis points, with fees sent to a configured recipient.
- **Client cancellation flow**:
  - funded jobs can be cancelled by the client before the freelancer accepts;
  - in-progress jobs can be cancelled by the client after the deadline has passed.
- **Refund handling** for cancelled jobs.
- **Custom errors and events** for clearer failure handling and easier indexing.
- **Foundry tests** covering the main happy paths, access control, validation rules, events, fees, refunds, deadline behavior, dispute opening rules, and dispute resolution rules.

## Contract overview

The main contract lives in:

```text
src/EscrowMarketplace.sol
```

### Job lifecycle

```text
Created/Funded → InProgress → Submitted → Completed
       │              │            │
       │              │            └── Disputed by client or freelancer
       │              ├── Disputed by client or freelancer
       │              └── Cancelled after deadline by client
       └── Cancelled before acceptance by client

Disputed → Completed after arbitrator resolution
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
- dispute reason URI

### Deployment configuration

The constructor requires:

- `feeRecipient`: address that receives platform fees.
- `platformFeeBps`: platform fee in basis points, capped at `10_000`.
- `arbitrator`: address allowed to resolve disputes.

## Main functions

| Function | Purpose |
| --- | --- |
| `createJob(...)` | Creates a job and transfers ERC20 funds into escrow. |
| `getJob(jobId)` | Returns the stored job data. |
| `acceptJob(jobId)` | Lets the assigned freelancer accept a funded job. |
| `submitWork(jobId, deliveryURI)` | Lets the freelancer submit work before the deadline. |
| `approveWork(jobId)` | Lets the client approve work and release payment minus platform fee. |
| `openDispute(jobId, reasonURI)` | Lets the client or freelancer open a dispute for an in-progress or submitted job. |
| `resolveDispute(jobId, clientAmount, freelancerAmount)` | Lets the configured arbitrator resolve a disputed job. The two amounts must add up to the escrowed job amount. Platform fees are charged only on the freelancer side. |
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
- Disputes can now be opened and resolved by the configured arbitrator.
- There is no admin function yet to update platform fees or the fee recipient after deployment.
- There is no admin function yet to update the arbitrator after deployment.
- The project has not been audited.
- Do not use this in production without a full security review.

## License

MIT
