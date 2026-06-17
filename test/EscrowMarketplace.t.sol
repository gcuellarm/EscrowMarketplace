// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EscrowMarketplace} from "../src/EscrowMarketplace.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract EscrowMarketplaceTest is Test {
    EscrowMarketplace marketplace;
    MockERC20 token;

    address client = makeAddr("client");
    address freelancer = makeAddr("freelancer");
    address stranger =makeAddr("stranger");

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

    event JobFunded(
        uint256 indexed jobId,
        address indexed client,
        address token,
        uint256 amount
    );

    event JobAccepted(
        uint256 indexed jobId,
        address indexed freelancer
    );

    // Helpers
    function _createJob() internal returns (uint256 jobId) {
        vm.startPrank(client);

        token.approve(address(marketplace), amount);

        jobId = marketplace.createJob({
            freelancer: freelancer,
            token: address(token),
            amount: amount,
            deadline: deadline,
            metadataURI: metadataURI
        });

        vm.stopPrank();
    }


    //Setup and tests
    function setUp() public {
        marketplace = new EscrowMarketplace();
        token = new MockERC20();

        deadline = block.timestamp + 7 days;

        token.mint(client, amount);
    }

    function test_CreateJob() public {
        vm.startPrank(client);

        token.approve(address(marketplace), amount);

        uint256 jobId = marketplace.createJob({
            freelancer: freelancer,
            token: address(token),
            amount: amount,
            deadline: deadline,
            metadataURI: metadataURI
        });

        vm.stopPrank();

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        assertEq(jobId, 1);
        assertEq(job.client, client);
        assertEq(job.freelancer, freelancer);
        assertEq(job.token, address(token));
        assertEq(job.amount, amount);
        assertEq(job.deadline, deadline);
        assertEq(uint256(job.status), uint256(EscrowMarketplace.JobStatus.Funded));
        assertEq(job.metadataURI, metadataURI);
    }

    function test_CreateJob_TransfersFundsToEscrow() public {
        uint256 clientBalanceBefore = token.balanceOf(client);
        uint256 marketplaceBalanceBefore = token.balanceOf(address(marketplace));

        vm.startPrank(client);

        token.approve(address(marketplace), amount);

        marketplace.createJob({
            freelancer: freelancer,
            token: address(token),
            amount: amount,
            deadline: deadline,
            metadataURI: metadataURI
        });

        vm.stopPrank();

        uint256 clientBalanceAfter = token.balanceOf(client);
        uint256 marketplaceBalanceAfter = token.balanceOf(address(marketplace));

        assertEq(clientBalanceBefore, amount);
        assertEq(marketplaceBalanceBefore, 0);

        assertEq(clientBalanceAfter, 0);
        assertEq(marketplaceBalanceAfter, amount);
    }

    function test_CreateJob_IncrementsNextJobId() public {
        vm.startPrank(client);

        token.approve(address(marketplace), amount);

        marketplace.createJob({
            freelancer: freelancer,
            token: address(token),
            amount: amount,
            deadline: deadline,
            metadataURI: metadataURI
        });

        vm.stopPrank();

        assertEq(marketplace.nextJobId(), 2);
    }

    function test_CreateMultipleJobs() public {
        uint256 secondAmount = amount * 2;

        token.mint(client, secondAmount);

        vm.startPrank(client);

        token.approve(address(marketplace), amount + secondAmount);

        uint256 firstJobId = marketplace.createJob({
            freelancer: freelancer,
            token: address(token),
            amount: amount,
            deadline: deadline,
            metadataURI: metadataURI
        });

        uint256 secondJobId = marketplace.createJob({
            freelancer: freelancer,
            token: address(token),
            amount: secondAmount,
            deadline: deadline + 1 days,
            metadataURI: "ipfs://second-job"
        });

        vm.stopPrank();

        EscrowMarketplace.Job memory firstJob = marketplace.getJob(firstJobId);
        EscrowMarketplace.Job memory secondJob = marketplace.getJob(secondJobId);

        assertEq(firstJobId, 1);
        assertEq(secondJobId, 2);

        assertEq(firstJob.amount, amount);
        assertEq(secondJob.amount, secondAmount);

        assertEq(firstJob.metadataURI, metadataURI);
        assertEq(secondJob.metadataURI, "ipfs://second-job");

        assertEq(uint256(firstJob.status), uint256(EscrowMarketplace.JobStatus.Funded));
        assertEq(uint256(secondJob.status), uint256(EscrowMarketplace.JobStatus.Funded));

        assertEq(token.balanceOf(address(marketplace)), amount + secondAmount);
        assertEq(marketplace.nextJobId(), 3);
    }

    function test_CreateJob_EmitsJobCreatedEvent() public {
        vm.startPrank(client);

        token.approve(address(marketplace), amount);

        vm.expectEmit(true, true, true, true);

        emit JobCreated(
            1,
            client,
            freelancer,
            address(token),
            amount,
            deadline,
            metadataURI
        );

        marketplace.createJob({
            freelancer: freelancer,
            token: address(token),
            amount: amount,
            deadline: deadline,
            metadataURI: metadataURI
        });

        vm.stopPrank();
    }

    function test_CreateJob_EmitsJobFundedEvent() public {
        vm.startPrank(client);

        token.approve(address(marketplace), amount);

        vm.expectEmit(true, true, false, true);

        emit JobFunded(
            1,
            client,
            address(token),
            amount
        );

        marketplace.createJob({
            freelancer: freelancer,
            token: address(token),
            amount: amount,
            deadline: deadline,
            metadataURI: metadataURI
        });

        vm.stopPrank();
    }

    function test_RevertIf_FreelancerIsZeroAddress() public {
        vm.startPrank(client);

        token.approve(address(marketplace), amount);

        vm.expectRevert(EscrowMarketplace.InvalidAddress.selector);

        marketplace.createJob({
            freelancer: address(0),
            token: address(token),
            amount: amount,
            deadline: deadline,
            metadataURI: metadataURI
        });

        vm.stopPrank();
    }

    function test_RevertIf_TokenIsZeroAddress() public {
        vm.startPrank(client);

        token.approve(address(marketplace), amount);

        vm.expectRevert(EscrowMarketplace.InvalidAddress.selector);

        marketplace.createJob({
            freelancer: freelancer,
            token: address(0),
            amount: amount,
            deadline: deadline,
            metadataURI: metadataURI
        });

        vm.stopPrank();
    }

    function test_RevertIf_FreelancerIsClient() public {
        vm.startPrank(client);

        token.approve(address(marketplace), amount);

        vm.expectRevert(EscrowMarketplace.InvalidFreelancer.selector);

        marketplace.createJob({
            freelancer: client,
            token: address(token),
            amount: amount,
            deadline: deadline,
            metadataURI: metadataURI
        });

        vm.stopPrank();
    }

    function test_RevertIf_AmountIsZero() public {
        vm.startPrank(client);

        token.approve(address(marketplace), amount);

        vm.expectRevert(EscrowMarketplace.InvalidAmount.selector);

        marketplace.createJob({
            freelancer: freelancer,
            token: address(token),
            amount: 0,
            deadline: deadline,
            metadataURI: metadataURI
        });

        vm.stopPrank();
    }

    function test_RevertIf_DeadlineIsCurrentTimestamp() public {
        vm.startPrank(client);

        token.approve(address(marketplace), amount);

        vm.expectRevert(EscrowMarketplace.InvalidDeadline.selector);

        marketplace.createJob({
            freelancer: freelancer,
            token: address(token),
            amount: amount,
            deadline: block.timestamp,
            metadataURI: metadataURI
        });

        vm.stopPrank();
    }

    function test_RevertIf_DeadlineIsInThePast() public {
        vm.warp(10 days);

        vm.startPrank(client);

        token.approve(address(marketplace), amount);

        vm.expectRevert(EscrowMarketplace.InvalidDeadline.selector);

        marketplace.createJob({
            freelancer: freelancer,
            token: address(token),
            amount: amount,
            deadline: block.timestamp - 1,
            metadataURI: metadataURI
        });

        vm.stopPrank();
    }

    function test_RevertIf_ClientHasNotApprovedMarketplace() public {
        vm.prank(client);

        vm.expectRevert();

        marketplace.createJob({
            freelancer: freelancer,
            token: address(token),
            amount: amount,
            deadline: deadline,
            metadataURI: metadataURI
        });
    }

    function test_RevertIf_ClientHasInsufficientBalance() public {
        uint256 excessiveAmount = amount + 1;

        vm.startPrank(client);

        token.approve(address(marketplace), excessiveAmount);

        vm.expectRevert();

        marketplace.createJob({
            freelancer: freelancer,
            token: address(token),
            amount: excessiveAmount,
            deadline: deadline,
            metadataURI: metadataURI
        });

        vm.stopPrank();
    }

    function test_RevertIf_JobDoesNotExist() public {
        vm.expectRevert(EscrowMarketplace.JobDoesNotExist.selector);

        marketplace.getJob(1);
    }

    function test_RevertIf_JobIdIsZero() public {
        vm.expectRevert(EscrowMarketplace.JobDoesNotExist.selector);

        marketplace.getJob(0);
    }

    function test_FreelancerCanAcceptJob() public {
        uint256 jobId = _createJob();

        vm.prank(freelancer);
        marketplace.acceptJob(jobId);

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        assertEq(uint256(job.status), uint256(EscrowMarketplace.JobStatus.InProgress));
    }

    function test_AcceptJob_EmitsEvent() public {
        uint256 jobId = _createJob();

        vm.expectEmit(true, true, false, true);
        emit JobAccepted(jobId, freelancer);
        
        vm.prank(freelancer);
        marketplace.acceptJob(jobId);
    }

    function test_RevertIf_ClientTriesToAcceptJob() public {
        uint256 jobId = _createJob();

        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);

        vm.prank(client);
        marketplace.acceptJob(jobId);
    }

    function test_RevertIf_StrangerTriesToAcceptJob() public {
        uint256 jobId = _createJob();

        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);

        vm.prank(stranger);
        marketplace.acceptJob(jobId);
    }

    function test_RevertIf_JobIsAlreadyAccepted() public {
        uint256 jobId = _createJob();

        vm.prank(freelancer);
        marketplace.acceptJob(jobId);

        vm.expectRevert(EscrowMarketplace.InvalidJobStatus.selector);

        vm.prank(freelancer);
        marketplace.acceptJob(jobId);
    }

    function test_RevertIf_AcceptedJobDoesNotExist() public {
        vm.expectRevert(EscrowMarketplace.JobDoesNotExist.selector);
        
        vm.prank(freelancer);
        marketplace.acceptJob(1);
    } 

    function test_RevertIf_AcceptedJobIdIsZero() public {
        vm.expectRevert(EscrowMarketplace.JobDoesNotExist.selector);
        
        vm.prank(freelancer);
        marketplace.acceptJob(0);
    }
}
