// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {EscrowMarketplace} from "../../src/EscrowMarketplace.sol";

import {MockERC20} from "../mocks/MockERC20.sol";

import {EscrowMarketplaceHandler} from "./EscrowMarketplaceHandler.sol";

contract EscrowMarketplaceInvariant is StdInvariant, Test {
    EscrowMarketplace public marketplace;
    MockERC20 public token;

    EscrowMarketplaceHandler public handler;

    address feeRecipient = makeAddr("feeRecipient");

    address arbitrator = makeAddr("arbitrator");

    uint256 platformFeeBps = 500;

    uint256 reviewPeriod = 3 days;

    function setUp() public {
        marketplace = new EscrowMarketplace(feeRecipient, platformFeeBps, arbitrator, reviewPeriod);

        token = new MockERC20();

        handler = new EscrowMarketplaceHandler(marketplace, token);

        targetContract(address(handler));
    }

    function invariant_EscrowedNeverExceedsBalance() public view {
        uint256 balance = token.balanceOf(address(marketplace));

        uint256 escrowed = marketplace.totalEscrowed(address(token));

        assertLe(escrowed, balance);
    }

    function invariant_ERC20BalanceMatchesEscrow() public view {
        assertEq(token.balanceOf(address(marketplace)), marketplace.totalEscrowed(address(token)));
    }

    function invariant_TotalEscrowedMatchesActiveJobs() public view {
        uint256 expectedEscrowed;

        uint256 length = handler.createdJobIdsLength();

        for (uint256 i = 0; i < length; ++i) {
            uint256 jobId = handler.createdJobIds(i);

            EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

            if (job.status == EscrowMarketplace.JobStatus.Funded || job.status == EscrowMarketplace.JobStatus.InProgress || job.status == EscrowMarketplace.JobStatus.Submitted || job.status == EscrowMarketplace.JobStatus.Disputed) {
                expectedEscrowed += job.amount;
            }
        }

        assertEq(marketplace.totalEscrowed(address(token)), expectedEscrowed);
    }
}
