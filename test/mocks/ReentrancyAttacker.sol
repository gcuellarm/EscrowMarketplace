// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EscrowMarketplace} from "../../src/EscrowMarketplace.sol";

/// @title ReentrancyAttacker
/// @notice Test helper that attempts to reenter a freelancer claim during an ETH transfer.
contract ReentrancyAttacker {
    /// @notice Marketplace targeted by the reentrancy attempt.
    EscrowMarketplace public marketplace;

    /// @notice Job used for the nested claim attempt.
    uint256 public jobId;
    /// @notice Whether the receive hook attempted a nested claim.
    bool public attackAttempted;
    /// @notice Whether the nested claim unexpectedly succeeded.
    bool public attackSucceeded;

    /// @notice Configures the marketplace targeted by this helper.
    /// @param marketplaceAddress Address of the deployed marketplace.
    constructor(
        address marketplaceAddress
    ) {
        marketplace =
            EscrowMarketplace(
                payable(marketplaceAddress)
            );
    }

    /// @notice Selects the job used by the reentrancy attempt.
    /// @param newJobId Identifier of the submitted job.
    function setJobId(
        uint256 newJobId
    ) external {
        jobId = newJobId;
    }

    /// @notice Attempts one nested claim when the marketplace sends ETH to this contract.
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
