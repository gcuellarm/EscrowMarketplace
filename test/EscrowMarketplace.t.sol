// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EscrowMarketplace} from "../src/EscrowMarketplace.sol";

contract EscrowMarketplaceTest is Test {
    EscrowMarketplace marketplace;

    address client = makeAddr("client");
    address freelancer = makeAddr("freelancer");
    address token = makeAddr("token");

    uint256 amount = 1_000e18;
    uint256 deadline;

    string metadataURI = "ipfs://job-metadata";

    event JobCreated(
        uint256 indexed jobId,
        address indexed client,
        address indexed freelancer,
        address token,
        uint256 amount,
        uint256 deadline,
        string metadataURI
    );

    function setUp() public {
        marketplace = new EscrowMarketplace();

        deadline = block.timestamp + 7 days;
    }

    function test_CreateJob() public {
        vm.prank(client);

        uint256 jobId = marketplace.createJob({
            freelancer: freelancer,
            token: token,
            amount: amount,
            deadline: deadline,
            metadataURI: metadataURI
        });

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        assertEq(jobId, 1);
        assertEq(job.client, client);
        assertEq(job.freelancer, freelancer);
        assertEq(job.token, token);
        assertEq(job.amount, amount);
        assertEq(job.deadline, deadline);
        assertEq(uint256(job.status), uint256(EscrowMarketplace.JobStatus.Created));
        assertEq(job.metadataURI, metadataURI);
    }

    function test_CreateJob_IncrementsNextJobId() public {
        vm.prank(client);

        marketplace.createJob({
            freelancer: freelancer,
            token: token,
            amount: amount,
            deadline: deadline,
            metadataURI: metadataURI
        });

        assertEq(marketplace.nextJobId(), 2);
    }

    function test_CreateMultipleJobs() public {
        vm.prank(client);

        uint256 firstJobId = marketplace.createJob({
            freelancer: freelancer,
            token: token,
            amount: amount,
            deadline: deadline,
            metadataURI: metadataURI
        });

        vm.prank(client);

        uint256 secondJobId = marketplace.createJob({
            freelancer: freelancer,
            token: token,
            amount: amount * 2,
            deadline: deadline + 1 days,
            metadataURI: "ipfs://second-job"
        });

        EscrowMarketplace.Job memory firstJob = marketplace.getJob(firstJobId);
        EscrowMarketplace.Job memory secondJob = marketplace.getJob(secondJobId);

        assertEq(firstJobId, 1);
        assertEq(secondJobId, 2);

        assertEq(firstJob.amount, amount);
        assertEq(secondJob.amount, amount * 2);

        assertEq(firstJob.metadataURI, metadataURI);
        assertEq(secondJob.metadataURI, "ipfs://second-job");

        assertEq(marketplace.nextJobId(), 3);
    }

    function test_CreateJob_EmitsEvent() public {
        vm.expectEmit(true, true, true, true);

        emit JobCreated(
            1,
            client,
            freelancer,
            token,
            amount,
            deadline,
            metadataURI
        );

        vm.prank(client);

        marketplace.createJob({
            freelancer: freelancer,
            token: token,
            amount: amount,
            deadline: deadline,
            metadataURI: metadataURI
        });
    }

    function test_RevertIf_FreelancerIsZeroAddress() public {
        vm.prank(client);

        vm.expectRevert(EscrowMarketplace.InvalidAddress.selector);

        marketplace.createJob({
            freelancer: address(0),
            token: token,
            amount: amount,
            deadline: deadline,
            metadataURI: metadataURI
        });
    }

    function test_RevertIf_TokenIsZeroAddress() public {
        vm.prank(client);

        vm.expectRevert(EscrowMarketplace.InvalidAddress.selector);

        marketplace.createJob({
            freelancer: freelancer,
            token: address(0),
            amount: amount,
            deadline: deadline,
            metadataURI: metadataURI
        });
    }

    function test_RevertIf_FreelancerIsClient() public {
        vm.prank(client);

        vm.expectRevert(EscrowMarketplace.InvalidFreelancer.selector);

        marketplace.createJob({
            freelancer: client,
            token: token,
            amount: amount,
            deadline: deadline,
            metadataURI: metadataURI
        });
    }

    function test_RevertIf_AmountIsZero() public {
        vm.prank(client);

        vm.expectRevert(EscrowMarketplace.InvalidAmount.selector);

        marketplace.createJob({
            freelancer: freelancer,
            token: token,
            amount: 0,
            deadline: deadline,
            metadataURI: metadataURI
        });
    }

    function test_RevertIf_DeadlineIsCurrentTimestamp() public {
        vm.prank(client);

        vm.expectRevert(EscrowMarketplace.InvalidDeadline.selector);

        marketplace.createJob({
            freelancer: freelancer,
            token: token,
            amount: amount,
            deadline: block.timestamp,
            metadataURI: metadataURI
        });
    }

    function test_RevertIf_DeadlineIsInThePast() public {
        vm.warp(10 days);

        vm.prank(client);

        vm.expectRevert(EscrowMarketplace.InvalidDeadline.selector);

        marketplace.createJob({
            freelancer: freelancer,
            token: token,
            amount: amount,
            deadline: block.timestamp - 1,
            metadataURI: metadataURI
        });
    }

    function test_RevertIf_JobDoesNotExist() public {
        vm.expectRevert(EscrowMarketplace.JobDoesNotExist.selector);

        marketplace.getJob(1);
    }

    function test_RevertIf_JobIdIsZero() public {
        vm.expectRevert(EscrowMarketplace.JobDoesNotExist.selector);

        marketplace.getJob(0);
    }
}