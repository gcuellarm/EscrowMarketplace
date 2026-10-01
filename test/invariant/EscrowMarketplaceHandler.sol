// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EscrowMarketplace} from "../../src/EscrowMarketplace.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract EscrowMarketplaceHandler is Test {
    EscrowMarketplace public marketplace;
    MockERC20 public token;

    address public client;
    address public freelancer;

    uint256 public constant MAX_AMOUNT = 1_000_000 ether;

    uint256[] public createdJobIds;

    constructor(EscrowMarketplace _marketplace, MockERC20 _token) {
        marketplace = _marketplace;
        token = _token;

        client = makeAddr("handlerClient");
        freelancer = makeAddr("handlerFreelancer");
    }

    function createJob(uint256 rawAmount) external {
        uint256 amount = bound(rawAmount, 1, MAX_AMOUNT);

        token.mint(client, amount);

        vm.startPrank(client);
        token.approve(address(marketplace), amount);

        uint256 jobId = marketplace.createJob(freelancer, address(token), amount, block.timestamp + 30 days, "ipfs://invariant-job");

        vm.stopPrank();

        createdJobIds.push(jobId);
    }

    function acceptJob(uint256 seed) external {
        uint256 jobId = _getJobId(seed);

        if (jobId == 0) {
            return;
        }

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        if (job.status != EscrowMarketplace.JobStatus.Funded) {
            return;
        }

        vm.prank(job.freelancer);
        marketplace.acceptJob(jobId);
    }

    function submitWork(uint256 seed) external {
        uint256 jobId = _getJobId(seed);

        if (jobId == 0) {
            return;
        }

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        if (job.status != EscrowMarketplace.JobStatus.InProgress) {
            return;
        }

        if (block.timestamp > job.deadline) {
            return;
        }

        vm.prank(job.freelancer);
        marketplace.submitWork(jobId, "ipfs://invariant-delivery");
    }

    function approveWork(uint256 seed) external {
        uint256 jobId = _getJobId(seed);

        if (jobId == 0) {
            return;
        }

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        if (job.status != EscrowMarketplace.JobStatus.Submitted) {
            return;
        }

        vm.prank(job.client);
        marketplace.approveWork(jobId);
    }

    function cancelJob(uint256 seed) external {
        uint256 jobId = _getJobId(seed);

        if (jobId == 0) {
            return;
        }

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        if (job.status != EscrowMarketplace.JobStatus.Funded) {
            return;
        }

        vm.prank(job.client);
        marketplace.cancelJob(jobId);
    }

    function openDispute(uint256 seed) external {
        uint256 jobId = _getJobId(seed);

        if (jobId == 0) {
            return;
        }

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        if (job.status != EscrowMarketplace.JobStatus.InProgress && job.status != EscrowMarketplace.JobStatus.Submitted) {
            return;
        }

        vm.prank(job.client);
        marketplace.openDispute(jobId, "ipfs://invariant-dispute");
    }

    function resolveDispute(uint256 seed, uint256 rawClientAmount) external {
        uint256 jobId = _getJobId(seed);

        if (jobId == 0) {
            return;
        }

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        if (job.status != EscrowMarketplace.JobStatus.Disputed) {
            return;
        }

        uint256 clientAmount = bound(rawClientAmount, 0, job.amount);

        uint256 freelancerAmount = job.amount - clientAmount;

        vm.prank(marketplace.arbitrator());
        marketplace.resolveDispute(jobId, clientAmount, freelancerAmount);
    }

    function createdJobIdsLength() external view returns (uint256) {
        return createdJobIds.length;
    }

    function _getJobId(uint256 seed) internal view returns (uint256) {
        if (createdJobIds.length == 0) {
            return 0;
        }

        return createdJobIds[seed % createdJobIds.length];
    }
}