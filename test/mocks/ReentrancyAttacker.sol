// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EscrowMarketplace} from "../../src/EscrowMarketplace.sol";

contract ReentrancyAttacker {
    EscrowMarketplace public marketplace;

    uint256 public jobId;
    bool public attackAttempted;
    bool public attackSucceeded;

    constructor(
        address marketplaceAddress
    ) {
        marketplace =
            EscrowMarketplace(
                payable(marketplaceAddress)
            );
    }

    function setJobId(
        uint256 newJobId
    ) external {
        jobId = newJobId;
    }

    receive() external payable {
        if (!attackAttempted) {
            attackAttempted = true;

            try marketplace.claimAfterReviewPeriod(
                jobId
            ) {
                attackSucceeded = true;
            } catch {
                attackSucceeded = false;
            }
        }
    }
}