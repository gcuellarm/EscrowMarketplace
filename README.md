# EscrowMarketplace 🛡️

A Foundry-based Solidity escrow marketplace where clients fund freelance jobs with native ETH or ERC20 tokens, freelancers deliver work, and escrow is settled through client approval, a time-based freelancer claim, cancellation, or arbitrator dispute resolution.

> Current status: the core escrow lifecycle, administration, asset accounting, recovery safeguards, and unit, fuzz, and invariant test suites are implemented. This project has not been audited and is not production-ready.

## What is implemented so far ✅

- **Native ETH and ERC20-funded jobs**. ERC20 transfers use OpenZeppelin `SafeERC20`; the zero address identifies native ETH.
- **Job creation with upfront funding**: a client creates a job and deposits the full payment into escrow in one transaction.
- **Freelancer assignment and job histories**: each job belongs to one client and one freelancer, with ordered ID histories and count helpers for both roles.
- **Off-chain metadata support** through `metadataURI`, `deliveryURI`, and `disputeReasonURI` fields, suitable for IPFS or another URI-based storage layer.
- **Work acceptance and submission**: the assigned freelancer accepts the job and submits work on or before the deadline.
- **Client approval**: the client can approve submitted work and release the net payment to the freelancer.
- **Freelancer claim after review**: if submitted work remains unresolved for the configured review period, the freelancer can claim payment without client action.
- **Dispute opening and resolution**: either party can dispute an in-progress or submitted job, and the configured arbitrator can split the complete escrow between client and freelancer.
- **Platform fees in basis points**: fees are deducted only from amounts allocated to the freelancer and sent to the configured fee recipient.
- **Client cancellation and refunds**:
  - funded jobs can be cancelled before freelancer acceptance;
  - in-progress jobs can be cancelled after the deadline has passed.
- **Per-asset escrow accounting** through `totalEscrowed`, independently tracking native ETH and every ERC20 token.
- **Safe surplus recovery**: the owner can recover accidentally sent ETH or ERC20 tokens without withdrawing funds reserved for active jobs.
- **Owner administration** for the fee recipient, platform fee, arbitrator, review period, and emergency pause state.
- **Reentrancy protection** on funding and every function that transfers assets out of the contract.
- **Custom errors and events** for explicit failure handling and off-chain indexing.
- **Foundry unit, edge-case, and fuzz tests** covering ETH and ERC20 flows, lifecycle transitions, boundary conditions, permissions, validation, events, fees, refunds, disputes, review-period claims, pausing, recovery limits, escrow accounting, histories, transfer rollback, dynamic configuration, and an ETH reentrancy attempt.
- **Stateful invariant tests** checking that ERC20 reserves never exceed the contract balance, exact-balance accounting under the handler's supported actions, and agreement between `totalEscrowed` and active jobs.
- **GitHub Actions CI** configured to build the contracts and run the complete Forge test suite on pushes and pull requests.

## Contract overview

The main contract lives in:

```text
src/EscrowMarketplace.sol
```

### Job lifecycle

```text
Funded ──accept──> InProgress ──submit──> Submitted ──approve/claim──> Completed
  │                    │                     │
  │                    ├── dispute ──────────┴──> Disputed ──resolve──> Completed
  │                    └── cancel after deadline ─────────────────────> Cancelled
  └── cancel before acceptance ───────────────────────────────────────> Cancelled
```

> Note: `createJob` creates and funds the job atomically, so jobs are stored as `Funded` immediately. The `Created` and `Approved` enum values are currently reserved and are not persisted during the implemented flow.

### Job data

Each job stores:

- client address
- freelancer address
- payment token address (`address(0)` for native ETH)
- gross escrowed amount
- work deadline
- submission timestamp
- current lifecycle status
- metadata URI
- delivery URI
- dispute reason URI

### Deployment configuration

The constructor requires:

- `feeRecipient_`: non-zero address that receives platform fees.
- `platformFeeBps_`: platform fee in basis points, from `0` to `10_000` inclusive.
- `arbitrator_`: non-zero address authorized to resolve disputes.
- `reviewPeriod_`: non-zero waiting period, in seconds, before a freelancer may claim submitted work.

The deployer becomes the owner. Job IDs start at `1`.

## Main functions

| Function | Purpose |
| --- | --- |
| `createJob(...)` | Creates a job and funds it with exact native ETH or an approved ERC20 amount. |
| `getJob(jobId)` | Returns all stored data for an existing job. |
| `acceptJob(jobId)` | Lets the assigned freelancer accept a funded job. |
| `submitWork(jobId, deliveryURI)` | Lets the freelancer submit work on or before the deadline. |
| `approveWork(jobId)` | Lets the client approve submitted work and release payment minus the platform fee. |
| `claimAfterReviewPeriod(jobId)` | Lets the freelancer claim submitted work after the review period expires. |
| `openDispute(jobId, reasonURI)` | Lets the client or freelancer dispute an in-progress or submitted job. |
| `resolveDispute(jobId, clientAmount, freelancerAmount)` | Lets the arbitrator allocate the full escrow. Fees apply only to the freelancer allocation. |
| `cancelJob(jobId)` | Lets the client cancel a funded job before acceptance and receive a full refund. |
| `cancelExpiredJob(jobId)` | Lets the client cancel an in-progress job after its deadline and receive a full refund. |
| `getClientJobIds(client)` / `getFreelancerJobIds(freelancer)` | Return ordered job ID histories for each role. |
| `getClientJobCount(client)` / `getFreelancerJobCount(freelancer)` | Return the number of jobs associated with each role. |
| `setFeeRecipient(...)` | Lets the owner update the fee recipient. |
| `setPlatformFee(...)` | Lets the owner update the fee from `0` to `10_000` basis points. |
| `setArbitrator(...)` | Lets the owner update the arbitrator. |
| `setReviewPeriod(...)` | Lets the owner update the non-zero review period. |
| `recoverERC20(...)` / `recoverETH(...)` | Let the owner recover only balances above active escrow reserves. |
| `pause()` / `unpause()` | Let the owner stop or resume lifecycle-changing marketplace operations. |

## Tech stack 🧰

- [Solidity](https://soliditylang.org/) `^0.8.24`
- [Foundry](https://book.getfoundry.sh/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/) (`SafeERC20`, `ReentrancyGuard`, and the test ERC20 implementation)
- Forge unit tests, cheatcodes, event assertions, and gas snapshots
- GitHub Actions CI

## Project structure

```text
src/
  EscrowMarketplace.sol        # Main escrow marketplace contract

test/
  EscrowMarketplace.t.sol      # Unit tests for the complete marketplace workflow
  EscrowMarketplaceEdgeCases.t.sol # Boundary, rollback, and configuration edge cases
  EscrowMarketplaceFuzz.t.sol  # Property-oriented fuzz tests for amounts and allocations
  invariant/
    EscrowMarketplaceHandler.sol     # Stateful action handler
    EscrowMarketplaceInvariant.t.sol # Escrow accounting invariants
  mocks/MockERC20.sol          # Mintable ERC20 test token
  mocks/ReentrancyAttacker.sol # ETH receiver used to test reentrancy protection

.github/workflows/test.yml     # CI build and test workflow
.gas-snapshot                  # Recorded gas usage for the Forge tests
foundry.toml                   # Foundry and lint configuration
remappings.txt                 # Solidity import remappings
```

## Getting started

Clone the repository with its submodules, or install the dependencies if needed:

```shell
git submodule update --init --recursive
forge install
```

Run the test suite:

```shell
forge test
```

Run one suite in isolation:

```shell
forge test --match-path test/EscrowMarketplace.t.sol
forge test --match-path test/EscrowMarketplaceEdgeCases.t.sol
forge test --match-path test/EscrowMarketplaceFuzz.t.sol
forge test --match-path 'test/invariant/*.t.sol'
```

Run tests with a gas report or refresh the committed snapshot:

```shell
forge test --gas-report
forge snapshot
```

Format and lint the code:

```shell
forge fmt
forge lint
```

## Important notes ⚠️

- Native ETH jobs require `msg.value == amount`; ERC20 jobs reject any attached ETH and require prior token approval.
- The contract assumes conventional ERC20 behavior through `SafeERC20`. Fee-on-transfer or rebasing tokens can break the expected one-to-one escrow accounting and are not explicitly supported.
- The platform fee is read at settlement time, not snapshotted when a job is created. Owner fee changes therefore affect existing unsettled jobs.
- The review period is also read at claim time. Updating it can change when an already submitted job becomes claimable.
- Pausing blocks job creation and lifecycle transitions, but read operations, owner configuration, and surplus recovery remain available.
- Metadata and delivery content live off-chain; the contract stores only their URI strings and does not validate their contents or availability.
- The owner and arbitrator are privileged roles. Ownership transfer and renunciation are not currently implemented.
- `Created` and `Approved` are reserved enum values; the implemented lifecycle stores new jobs as `Funded` and settled jobs as `Completed`.
- Surplus recovery protects the amount tracked in `totalEscrowed`, but unsupported token mechanics can invalidate that accounting assumption.
- The contract has not been audited. Do not use it in production without a full security review and deployment-specific threat modelling.

## License

MIT
