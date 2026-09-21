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
    address stranger = makeAddr("stranger");
    address recipient = makeAddr("recipient");

    uint256 amount = 1_000e18;
    uint256 deadline;

    string metadataURI = "ipfs://job-metadata";
    string deliveryURI = "ipfs://job-delivery";
    string disputeReasonURI = "ipfs://dispute-reason";

    address feeRecipient = makeAddr("feeRecipient");
    address arbitrator = makeAddr("arbitrator");

    uint256 platformFeeBps = 500;
    uint256 reviewPeriod = 3 days;

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

    event WorkSubmitted(
        uint256 indexed jobId,
        address indexed freelancer,
        string deliveryURI
    );

    event WorkApproved(
        uint256 indexed jobId,
        address indexed client
    );

    event PaymentReleased(
        uint256 indexed jobId,
        address indexed freelancer,
        uint256 freelancerAmount,
        uint256 platformFee
    );

    event JobCancelled(
        uint256 indexed jobId,
        address indexed client
    );

    event ClientRefunded(
        uint256 indexed jobId,
        address indexed client,
        uint256 amount
    );

    event DisputeOpened(
        uint256 indexed jobId,
        address indexed openedBy,
        string reasonURI
    );

    event DisputeResolved(
        uint256 indexed jobId,
        address indexed arbitrator,
        uint256 clientAmount,
        uint256 freelancerAmount
    );

    event PaymentClaimedAfterReview(
        uint256 indexed jobId,
        address indexed freelancer
    );

    event FeeRecipientUpdated(
        address indexed oldFeeRecipient,
        address indexed newFeeRecipient
    );

    event PlatformFeeUpdated(
        uint256 oldFeeBps,
        uint256 newFeeBps
    );

    event ArbitratorUpdated(
        address indexed oldArbitrator,
        address indexed newArbitrator
    );

    event ReviewPeriodUpdated(
        uint256 oldReviewPeriod,
        uint256 newReviewPeriod
    );

    event MarketPlacePaused(
        address indexed owner
    );

    event MarketPlaceUnpaused(
        address indexed owner
    );

    event ERC20Recovered(
        address indexed token,
        uint256 amount,
        address indexed recipient
    );

    event ERC20Recovered(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );



    ///////////////////////////////////////////
    // Helpers
    ///////////////////////////////////////////

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

    function _createAndAcceptJob() internal returns (uint256 jobId) {
        jobId = _createJob();

        vm.prank(freelancer);
        marketplace.acceptJob(jobId);
    }

    function _createAcceptAndSubmitJob() internal returns (uint256 jobId) {
        jobId = _createAndAcceptJob();

        vm.prank(freelancer);
        marketplace.submitWork(jobId, deliveryURI);
    }

    function _createAcceptSubmitAndDisputeJob() internal returns (uint256 jobId) {
        jobId = _createAcceptAndSubmitJob();

        vm.prank(client);
        marketplace.openDispute(jobId, disputeReasonURI);
    }

    ///////////////////////////////////////////
    // Setup
    ///////////////////////////////////////////

    function setUp() public {
        marketplace = new EscrowMarketplace(
            feeRecipient,
            platformFeeBps,
            arbitrator,
            reviewPeriod
        );

        token = new MockERC20();

        deadline = block.timestamp + 7 days;

        token.mint(client, amount);
    }

    ///////////////////////////////////////////
    // createJob Tests
    ///////////////////////////////////////////

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
        assertEq(job.submittedAt, 0);
        assertEq(uint256(job.status), uint256(EscrowMarketplace.JobStatus.Funded));
        assertEq(job.metadataURI, metadataURI);
        assertEq(job.deliveryURI, "");
        assertEq(job.disputeReasonURI, "");
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
        vm.expectRevert();

        vm.prank(client);
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

    ///////////////////////////////////////////
    // acceptJob Tests
    ///////////////////////////////////////////

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

    ///////////////////////////////////////////
    // submitWork Tests
    ///////////////////////////////////////////

    function test_FreelancerCanSubmitWork() public {
        uint256 jobId = _createAndAcceptJob();

        vm.prank(freelancer);
        marketplace.submitWork(jobId, deliveryURI);

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        assertEq(uint256(job.status), uint256(EscrowMarketplace.JobStatus.Submitted));
        assertEq(job.deliveryURI, deliveryURI);
        assertEq(job.submittedAt, block.timestamp);
    }

    function test_SubmitWork_EmitsEvent() public {
        uint256 jobId = _createAndAcceptJob();

        vm.expectEmit(true, true, false, true);
        emit WorkSubmitted(jobId, freelancer, deliveryURI);

        vm.prank(freelancer);
        marketplace.submitWork(jobId, deliveryURI);
    }

    function test_RevertIf_ClientTriesToSubmitWork() public {
        uint256 jobId = _createAndAcceptJob();

        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);

        vm.prank(client);
        marketplace.submitWork(jobId, deliveryURI);
    }

    function test_RevertIf_StrangerTriesToSubmitWork() public {
        uint256 jobId = _createAndAcceptJob();

        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);

        vm.prank(stranger);
        marketplace.submitWork(jobId, deliveryURI);
    }

    function test_RevertIf_JobIsNotInProgress() public {
        uint256 jobId = _createJob();

        vm.expectRevert(EscrowMarketplace.InvalidJobStatus.selector);

        vm.prank(freelancer);
        marketplace.submitWork(jobId, deliveryURI);
    }

    function test_RevertIf_WorkIsSubmittedTwice() public {
        uint256 jobId = _createAndAcceptJob();

        vm.prank(freelancer);
        marketplace.submitWork(jobId, deliveryURI);

        vm.expectRevert(EscrowMarketplace.InvalidJobStatus.selector);

        vm.prank(freelancer);
        marketplace.submitWork(jobId, deliveryURI);
    }

    function test_RevertIf_DeliveryURIIsEmpty() public {
        uint256 jobId = _createAndAcceptJob();

        vm.expectRevert(EscrowMarketplace.EmptyDeliveryURI.selector);

        vm.prank(freelancer);
        marketplace.submitWork(jobId, "");
    }

    function test_RevertIf_DeadlineHasPassed() public {
        uint256 jobId = _createAndAcceptJob();

        vm.warp(deadline + 1);

        vm.expectRevert(EscrowMarketplace.DeadlinePassed.selector);

        vm.prank(freelancer);
        marketplace.submitWork(jobId, deliveryURI);
    }

    function test_FreelancerCanSubmitExactlyAtDeadline() public {
        uint256 jobId = _createAndAcceptJob();

        vm.warp(deadline);

        vm.prank(freelancer);
        marketplace.submitWork(jobId, deliveryURI);

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        assertEq(uint256(job.status), uint256(EscrowMarketplace.JobStatus.Submitted));
        assertEq(job.deliveryURI, deliveryURI);
        assertEq(job.submittedAt, deadline);
    }

    function test_RevertIf_SubmittedJobDoesNotExist() public {
        vm.expectRevert(EscrowMarketplace.JobDoesNotExist.selector);

        vm.prank(freelancer);
        marketplace.submitWork(999, deliveryURI);
    }

    //////////////////////////////////////
    // Constructor / Fee Tests
    //////////////////////////////////////

    function test_ConstructorSetsFeeConfiguration() public view {
        assertEq(marketplace.feeRecipient(), feeRecipient);
        assertEq(marketplace.platformFeeBps(), platformFeeBps);
        assertEq(marketplace.arbitrator(), arbitrator);
        assertEq(marketplace.reviewPeriod(), reviewPeriod);
        assertEq(marketplace.BPS_DENOMINATOR(), 10_000);
        assertEq(marketplace.owner(), address(this));
        assertEq(marketplace.paused(), false);
    }

    function test_RevertIf_FeeRecipientIsZeroAddress() public {
        vm.expectRevert(EscrowMarketplace.InvalidAddress.selector);

        new EscrowMarketplace(
            address(0),
            platformFeeBps,
            arbitrator,
            reviewPeriod
        );
    }

    function test_RevertIf_PlatformFeeIsTooHigh() public {
        uint256 tooHighFee = 10_001;

        vm.expectRevert(EscrowMarketplace.InvalidFee.selector);

        new EscrowMarketplace(
            feeRecipient,
            tooHighFee,
            arbitrator,
            reviewPeriod
        );
    }

    function test_RevertIf_ArbitratorIsZeroAddress() public {
        vm.expectRevert(EscrowMarketplace.InvalidAddress.selector);

        new EscrowMarketplace(
            feeRecipient,
            platformFeeBps,
            address(0),
            reviewPeriod
        );
    }

    function test_RevertIf_ReviewPeriodIsZero() public {
        vm.expectRevert(EscrowMarketplace.InvalidReviewPeriod.selector);

        new EscrowMarketplace(
            feeRecipient,
            platformFeeBps,
            arbitrator,
            0
        );
    }

    //////////////////////////////////////
    // approveWork Tests
    //////////////////////////////////////

    function test_ClientCanApproveWork() public {
        uint256 jobId = _createAcceptAndSubmitJob();

        vm.prank(client);
        marketplace.approveWork(jobId);

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        assertEq(uint256(job.status), uint256(EscrowMarketplace.JobStatus.Completed));
    }

    function test_ApproveWork_ReleasesFunds() public {
        uint256 expectedFee = (amount * platformFeeBps) / marketplace.BPS_DENOMINATOR();
        uint256 expectedFreelancerAmount = amount - expectedFee;

        uint256 jobId = _createAcceptAndSubmitJob();

        assertEq(token.balanceOf(address(marketplace)), amount);
        assertEq(token.balanceOf(freelancer), 0);
        assertEq(token.balanceOf(feeRecipient), 0);

        vm.prank(client);
        marketplace.approveWork(jobId);

        assertEq(token.balanceOf(freelancer), expectedFreelancerAmount);
        assertEq(token.balanceOf(feeRecipient), expectedFee);
        assertEq(token.balanceOf(address(marketplace)), 0);
    }

    function test_ApproveWork_EmitsWorkApprovedEvent() public {
        uint256 jobId = _createAcceptAndSubmitJob();

        vm.expectEmit(true, true, false, true);
        emit WorkApproved(jobId, client);

        vm.prank(client);
        marketplace.approveWork(jobId);
    }

    function test_ApproveWork_EmitsPaymentReleasedEvent() public {
        uint256 expectedFee =
            (amount * platformFeeBps) / marketplace.BPS_DENOMINATOR();

        uint256 expectedFreelancerAmount = amount - expectedFee;

        uint256 jobId = _createAcceptAndSubmitJob();

        vm.expectEmit(true, true, false, true);

        emit PaymentReleased(
            jobId,
            freelancer,
            expectedFreelancerAmount,
            expectedFee
        );

        vm.prank(client);
        marketplace.approveWork(jobId);
    }

    function test_RevertIf_FreelancerTriesToApproveWork() public {
        uint256 jobId = _createAcceptAndSubmitJob();

        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);

        vm.prank(freelancer);
        marketplace.approveWork(jobId);
    }

    function test_RevertIf_StrangerTriesToApproveWork() public {
        uint256 jobId = _createAcceptAndSubmitJob();

        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);

        vm.prank(stranger);
        marketplace.approveWork(jobId);
    }

    function test_RevertIf_JobHasNotBeenSubmitted() public {
        uint256 jobId = _createAndAcceptJob();

        vm.expectRevert(EscrowMarketplace.InvalidJobStatus.selector);

        vm.prank(client);
        marketplace.approveWork(jobId);
    }

    function test_RevertIf_WorkIsApprovedTwice() public {
        uint256 jobId = _createAcceptAndSubmitJob();

        vm.prank(client);
        marketplace.approveWork(jobId);

        vm.expectRevert(EscrowMarketplace.InvalidJobStatus.selector);

        vm.prank(client);
        marketplace.approveWork(jobId);
    }

    function test_RevertIf_ApprovedJobDoesNotExist() public {
        vm.expectRevert(EscrowMarketplace.JobDoesNotExist.selector);

        vm.prank(client);
        marketplace.approveWork(1);
    }

    function test_WorksIf_FeeIsZero() public {
        EscrowMarketplace marketplaceWithZeroFee = new EscrowMarketplace(
            feeRecipient,
            0,
            arbitrator,
            reviewPeriod
        );

        vm.startPrank(client);
        token.approve(address(marketplaceWithZeroFee), amount);

        uint256 jobId = marketplaceWithZeroFee.createJob({
            freelancer: freelancer,
            token: address(token),
            amount: amount,
            deadline: deadline,
            metadataURI: metadataURI
        });

        vm.stopPrank();

        vm.prank(freelancer);
        marketplaceWithZeroFee.acceptJob(jobId);

        vm.prank(freelancer);
        marketplaceWithZeroFee.submitWork(jobId, deliveryURI);

        vm.prank(client);
        marketplaceWithZeroFee.approveWork(jobId);

        assertEq(token.balanceOf(freelancer), amount);
        assertEq(token.balanceOf(feeRecipient), 0);
        assertEq(token.balanceOf(address(marketplaceWithZeroFee)), 0);
    }

    ///////////////////////////////////////////
    // cancelJob / cancelExpiredJob Tests
    ///////////////////////////////////////////

    function test_ClientCanCancelFundedJob() public {
        uint256 jobId = _createJob();

        vm.prank(client);
        marketplace.cancelJob(jobId);

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        assertEq(
            uint256(job.status),
            uint256(EscrowMarketplace.JobStatus.Cancelled)
        );
    }

    function test_CancelJob_RefundsClient() public {
        uint256 jobId = _createJob();

        uint256 clientBalanceBefore = token.balanceOf(client);

        assertEq(clientBalanceBefore, 0);
        assertEq(token.balanceOf(address(marketplace)), amount);

        vm.prank(client);
        marketplace.cancelJob(jobId);

        uint256 clientBalanceAfter = token.balanceOf(client);

        assertEq(clientBalanceAfter, clientBalanceBefore + amount);
        assertEq(token.balanceOf(address(marketplace)), 0);
    }

    function test_CancelJob_EmitsJobCancelledEvent() public {
        uint256 jobId = _createJob();

        vm.expectEmit(true, true, false, true);
        emit JobCancelled(jobId, client);

        vm.prank(client);
        marketplace.cancelJob(jobId);
    }

    function test_CancelJob_EmitsClientRefundedEvent() public {
        uint256 jobId = _createJob();

        vm.expectEmit(true, true, false, true);
        emit ClientRefunded(jobId, client, amount);

        vm.prank(client);
        marketplace.cancelJob(jobId);
    }

    function test_RevertIf_FreelancerTriesToCancelJob() public {
        uint256 jobId = _createJob();

        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);

        vm.prank(freelancer);
        marketplace.cancelJob(jobId);
    }

    function test_RevertIf_CancelJobIsAlreadyInProgress() public {
        uint256 jobId = _createAndAcceptJob();

        vm.expectRevert(EscrowMarketplace.InvalidJobStatus.selector);

        vm.prank(client);
        marketplace.cancelJob(jobId);
    }

    function test_ClientCanCancelExpiredJob() public {
        uint256 jobId = _createAndAcceptJob();

        uint256 clientBalanceBefore = token.balanceOf(client);

        vm.warp(deadline + 1);

        vm.prank(client);
        marketplace.cancelExpiredJob(jobId);

        uint256 clientBalanceAfter = token.balanceOf(client);

        assertEq(
            uint256(marketplace.getJob(jobId).status),
            uint256(EscrowMarketplace.JobStatus.Cancelled)
        );

        assertEq(clientBalanceAfter, clientBalanceBefore + amount);
        assertEq(token.balanceOf(address(marketplace)), 0);
    }

    function test_RevertIf_ClientCancelsBeforeDeadline() public {
        uint256 jobId = _createAndAcceptJob();

        vm.expectRevert(EscrowMarketplace.DeadlineNotPassed.selector);

        vm.prank(client);
        marketplace.cancelExpiredJob(jobId);
    }

    function test_RevertIf_ClientCancelsExactlyAtDeadline() public {
        uint256 jobId = _createAndAcceptJob();

        vm.warp(deadline);

        vm.expectRevert(EscrowMarketplace.DeadlineNotPassed.selector);

        vm.prank(client);
        marketplace.cancelExpiredJob(jobId);
    }

    function test_RevertIf_FreelancerCancelsExpiredJob() public {
        uint256 jobId = _createAndAcceptJob();

        vm.warp(deadline + 1);

        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);

        vm.prank(freelancer);
        marketplace.cancelExpiredJob(jobId);
    }

    function test_RevertIf_CancelWhenJobDoesNotExist() public {
        vm.expectRevert(EscrowMarketplace.JobDoesNotExist.selector);

        vm.prank(client);
        marketplace.cancelJob(1);
    }

    function test_RevertIf_CancelExpiredJobDoesNotExist() public {
        vm.expectRevert(EscrowMarketplace.JobDoesNotExist.selector);

        vm.prank(client);
        marketplace.cancelExpiredJob(1);
    }

    function test_RevertIf_CancelExpiredJobIsAlreadyCancelled() public {
        uint256 jobId = _createAndAcceptJob();

        vm.warp(deadline + 1);

        vm.prank(client);
        marketplace.cancelExpiredJob(jobId);

        vm.expectRevert(EscrowMarketplace.InvalidJobStatus.selector);

        vm.prank(client);
        marketplace.cancelExpiredJob(jobId);
    }

    ///////////////////////////////////////////
    // openDispute Tests
    ///////////////////////////////////////////

    function test_ClientCanOpenDisputeWhileJobIsInProgress() public {
        uint256 jobId = _createAndAcceptJob();

        vm.prank(client);
        marketplace.openDispute(jobId, disputeReasonURI);

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        assertEq(uint256(job.status), uint256(EscrowMarketplace.JobStatus.Disputed));
        assertEq(job.disputeReasonURI, disputeReasonURI);
    }

    function test_FreelancerCanOpenDisputeWhileJobIsInProgress() public {
        uint256 jobId = _createAndAcceptJob();

        vm.prank(freelancer);
        marketplace.openDispute(jobId, disputeReasonURI);

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        assertEq(uint256(job.status), uint256(EscrowMarketplace.JobStatus.Disputed));
        assertEq(job.disputeReasonURI, disputeReasonURI);
    }

    function test_ClientCanOpenDisputeAfterWorkIsSubmitted() public {
        uint256 jobId = _createAcceptAndSubmitJob();

        vm.prank(client);
        marketplace.openDispute(jobId, disputeReasonURI);

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        assertEq(uint256(job.status), uint256(EscrowMarketplace.JobStatus.Disputed));
        assertEq(job.disputeReasonURI, disputeReasonURI);
    }

    function test_FreelancerCanOpenDisputeAfterWorkIsSubmitted() public {
        uint256 jobId = _createAcceptAndSubmitJob();

        vm.prank(freelancer);
        marketplace.openDispute(jobId, disputeReasonURI);

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        assertEq(uint256(job.status), uint256(EscrowMarketplace.JobStatus.Disputed));
        assertEq(job.disputeReasonURI, disputeReasonURI);
    }

    function test_OpenDispute_KeepsFundsInEscrow() public {
        uint256 jobId = _createAndAcceptJob();

        vm.prank(client);
        marketplace.openDispute(jobId, disputeReasonURI);

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        assertEq(token.balanceOf(address(marketplace)), job.amount);
    }

    function test_OpenDispute_EmitsEvent() public {
        uint256 jobId = _createAndAcceptJob();

        vm.expectEmit(true, true, false, true);
        emit DisputeOpened(jobId, client, disputeReasonURI);

        vm.prank(client);
        marketplace.openDispute(jobId, disputeReasonURI);
    }

    function test_RevertIf_StrangerTriesToOpenDispute() public {
        uint256 jobId = _createAndAcceptJob();

        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);

        vm.prank(stranger);
        marketplace.openDispute(jobId, disputeReasonURI);
    }

    function test_RevertIf_DisputeIsOpenedBeforeJobAcceptance() public {
        uint256 jobId = _createJob();

        vm.expectRevert(EscrowMarketplace.InvalidJobStatus.selector);

        vm.prank(client);
        marketplace.openDispute(jobId, disputeReasonURI);
    }

    function test_RevertIf_DisputeIsAlreadyOpen() public {
        uint256 jobId = _createAndAcceptJob();

        vm.prank(client);
        marketplace.openDispute(jobId, disputeReasonURI);

        vm.expectRevert(EscrowMarketplace.InvalidJobStatus.selector);

        vm.prank(freelancer);
        marketplace.openDispute(jobId, "ipfs://another-reason");
    }

    function test_RevertIf_DisputeReasonURIIsEmpty() public {
        uint256 jobId = _createAndAcceptJob();

        vm.expectRevert(EscrowMarketplace.EmptyDisputeReasonURI.selector);

        vm.prank(client);
        marketplace.openDispute(jobId, "");
    }

    function test_RevertIf_DisputedJobDoesNotExist() public {
        vm.expectRevert(EscrowMarketplace.JobDoesNotExist.selector);

        vm.prank(client);
        marketplace.openDispute(1, disputeReasonURI);
    }

    function test_RevertIf_DisputedJobIdIsZero() public {
        vm.expectRevert(EscrowMarketplace.JobDoesNotExist.selector);

        vm.prank(client);
        marketplace.openDispute(0, disputeReasonURI);
    }

    function test_RevertIf_CancelledJobIsDisputed() public {
        uint256 jobId = _createJob();

        vm.prank(client);
        marketplace.cancelJob(jobId);

        vm.expectRevert(EscrowMarketplace.InvalidJobStatus.selector);

        vm.prank(client);
        marketplace.openDispute(jobId, disputeReasonURI);
    }

    function test_RevertIf_CompletedJobIsDisputed() public {
        uint256 jobId = _createAcceptAndSubmitJob();

        vm.prank(client);
        marketplace.approveWork(jobId);

        vm.expectRevert(EscrowMarketplace.InvalidJobStatus.selector);

        vm.prank(client);
        marketplace.openDispute(jobId, disputeReasonURI);
    }

    function test_RevertIf_ClientApprovesDisputedJob() public {
        uint256 jobId = _createAcceptAndSubmitJob();

        vm.prank(client);
        marketplace.openDispute(jobId, disputeReasonURI);

        vm.expectRevert(EscrowMarketplace.InvalidJobStatus.selector);

        vm.prank(client);
        marketplace.approveWork(jobId);
    }

    ///////////////////////////////////////////
    // resolveDispute Tests
    ///////////////////////////////////////////

    function test_ConstructorSetsArbitrator() public view {
        assertEq(marketplace.arbitrator(), arbitrator);
    }

    function test_ArbitratorCanResolveDisputeFullyForClient() public {
        uint256 jobId = _createAcceptSubmitAndDisputeJob();

        vm.prank(arbitrator);
        marketplace.resolveDispute(jobId, amount, 0);

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        assertEq(
            uint256(job.status),
            uint256(EscrowMarketplace.JobStatus.Completed)
        );

        assertEq(token.balanceOf(client), amount);
        assertEq(token.balanceOf(freelancer), 0);
        assertEq(token.balanceOf(feeRecipient), 0);
        assertEq(token.balanceOf(address(marketplace)), 0);
    }

    function test_ArbitratorCanResolveDisputeFullyForFreelancer() public {
        uint256 expectedFee =
            (amount * platformFeeBps) / marketplace.BPS_DENOMINATOR();

        uint256 expectedFreelancerAmount = amount - expectedFee;

        uint256 jobId = _createAcceptSubmitAndDisputeJob();

        vm.prank(arbitrator);
        marketplace.resolveDispute(jobId, 0, amount);

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        assertEq(
            uint256(job.status),
            uint256(EscrowMarketplace.JobStatus.Completed)
        );

        assertEq(token.balanceOf(client), 0);
        assertEq(token.balanceOf(freelancer), expectedFreelancerAmount);
        assertEq(token.balanceOf(feeRecipient), expectedFee);
        assertEq(token.balanceOf(address(marketplace)), 0);
    }

    function test_ArbitratorCanResolveDisputePartially() public {
        uint256 clientAmount = amount / 2;
        uint256 freelancerAmount = amount / 2;

        uint256 expectedFee =
            (freelancerAmount * platformFeeBps) / marketplace.BPS_DENOMINATOR();

        uint256 expectedFreelancerAmount = freelancerAmount - expectedFee;

        uint256 jobId = _createAcceptSubmitAndDisputeJob();

        vm.prank(arbitrator);
        marketplace.resolveDispute(jobId, clientAmount, freelancerAmount);

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        assertEq(
            uint256(job.status),
            uint256(EscrowMarketplace.JobStatus.Completed)
        );

        assertEq(token.balanceOf(client), clientAmount);
        assertEq(token.balanceOf(freelancer), expectedFreelancerAmount);
        assertEq(token.balanceOf(feeRecipient), expectedFee);
        assertEq(token.balanceOf(address(marketplace)), 0);
    }

    function test_ResolveDispute_EmitsDisputeResolvedEvent() public {
        uint256 jobId = _createAcceptSubmitAndDisputeJob();

        uint256 clientAmount = amount / 2;
        uint256 freelancerAmount = amount / 2;

        vm.expectEmit(true, true, false, true);

        emit DisputeResolved(
            jobId,
            arbitrator,
            clientAmount,
            freelancerAmount
        );

        vm.prank(arbitrator);
        marketplace.resolveDispute(jobId, clientAmount, freelancerAmount);
    }

    function test_ResolveDispute_EmitsClientRefundedEvent() public {
        uint256 jobId = _createAcceptSubmitAndDisputeJob();

        vm.expectEmit(true, true, false, true);

        emit ClientRefunded(
            jobId,
            client,
            amount
        );

        vm.prank(arbitrator);
        marketplace.resolveDispute(jobId, amount, 0);
    }

    function test_ResolveDispute_EmitsPaymentReleasedEvent() public {
        uint256 expectedFee =
            (amount * platformFeeBps) / marketplace.BPS_DENOMINATOR();

        uint256 expectedFreelancerAmount = amount - expectedFee;

        uint256 jobId = _createAcceptSubmitAndDisputeJob();

        vm.expectEmit(true, true, false, true);

        emit PaymentReleased(
            jobId,
            freelancer,
            expectedFreelancerAmount,
            expectedFee
        );

        vm.prank(arbitrator);
        marketplace.resolveDispute(jobId, 0, amount);
    }

    function test_RevertIf_NonArbitratorTriesToResolveDispute() public {
        uint256 jobId = _createAcceptSubmitAndDisputeJob();

        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);

        vm.prank(client);
        marketplace.resolveDispute(jobId, amount, 0);
    }

    function test_RevertIf_FreelancerTriesToResolveDispute() public {
        uint256 jobId = _createAcceptSubmitAndDisputeJob();

        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);

        vm.prank(freelancer);
        marketplace.resolveDispute(jobId, amount, 0);
    }

    function test_RevertIf_StrangerTriesToResolveDispute() public {
        uint256 jobId = _createAcceptSubmitAndDisputeJob();

        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);

        vm.prank(stranger);
        marketplace.resolveDispute(jobId, amount, 0);
    }

    function test_RevertIf_JobIsNotDisputed() public {
        uint256 jobId = _createAcceptAndSubmitJob();

        vm.expectRevert(EscrowMarketplace.InvalidJobStatus.selector);

        vm.prank(arbitrator);
        marketplace.resolveDispute(jobId, amount, 0);
    }

    function test_RevertIf_ResolutionAmountsAreLowerThanJobAmount() public {
        uint256 jobId = _createAcceptSubmitAndDisputeJob();

        vm.expectRevert(EscrowMarketplace.InvalidResolutionAmounts.selector);

        vm.prank(arbitrator);
        marketplace.resolveDispute(jobId, amount - 1, 0);
    }

    function test_RevertIf_ResolutionAmountsAreHigherThanJobAmount() public {
        uint256 jobId = _createAcceptSubmitAndDisputeJob();

        vm.expectRevert(EscrowMarketplace.InvalidResolutionAmounts.selector);

        vm.prank(arbitrator);
        marketplace.resolveDispute(jobId, amount, 1);
    }

    function test_RevertIf_DisputeIsResolvedTwice() public {
        uint256 jobId = _createAcceptSubmitAndDisputeJob();

        vm.prank(arbitrator);
        marketplace.resolveDispute(jobId, amount, 0);

        vm.expectRevert(EscrowMarketplace.InvalidJobStatus.selector);

        vm.prank(arbitrator);
        marketplace.resolveDispute(jobId, amount, 0);
    }

    function test_RevertIf_ResolvedJobDoesNotExist() public {
        vm.expectRevert(EscrowMarketplace.JobDoesNotExist.selector);

        vm.prank(arbitrator);
        marketplace.resolveDispute(1, amount, 0);
    }

    function test_RevertIf_ResolvedJobIdIsZero() public {
        vm.expectRevert(EscrowMarketplace.JobDoesNotExist.selector);

        vm.prank(arbitrator);
        marketplace.resolveDispute(0, amount, 0);
    }

    ///////////////////////////////////////////
    // claimAfterReviewPeriod Tests
    ///////////////////////////////////////////

    function test_FreelancerCanClaimAfterReviewPeriod() public {
        uint256 jobId = _createAcceptAndSubmitJob();

        vm.warp(block.timestamp + reviewPeriod);

        vm.prank(freelancer);
        marketplace.claimAfterReviewPeriod(jobId);

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        assertEq(
            uint256(job.status),
            uint256(EscrowMarketplace.JobStatus.Completed)
        );
    }

    function test_ClaimAfterReviewPeriod_ReleasesFunds() public {
        uint256 expectedFee =
            (amount * platformFeeBps) / marketplace.BPS_DENOMINATOR();

        uint256 expectedFreelancerAmount = amount - expectedFee;

        uint256 jobId = _createAcceptAndSubmitJob();

        vm.warp(block.timestamp + reviewPeriod);

        vm.prank(freelancer);
        marketplace.claimAfterReviewPeriod(jobId);

        assertEq(token.balanceOf(freelancer), expectedFreelancerAmount);
        assertEq(token.balanceOf(feeRecipient), expectedFee);
        assertEq(token.balanceOf(address(marketplace)), 0);
        assertEq(token.balanceOf(client), 0);
    }

    function test_RevertIf_ReviewPeriodHasNotPassed() public {
        uint256 jobId = _createAcceptAndSubmitJob();

        vm.warp(block.timestamp + reviewPeriod - 1);

        vm.expectRevert(EscrowMarketplace.ReviewPeriodNotPassed.selector);

        vm.prank(freelancer);
        marketplace.claimAfterReviewPeriod(jobId);
    }

    function test_FreelancerCanClaimExactlyAfterReviewPeriod() public {
        uint256 jobId = _createAcceptAndSubmitJob();

        vm.warp(block.timestamp + reviewPeriod);

        vm.prank(freelancer);
        marketplace.claimAfterReviewPeriod(jobId);

        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);

        assertEq(
            uint256(job.status),
            uint256(EscrowMarketplace.JobStatus.Completed)
        );
    }

    function test_RevertIf_ClientTriesToClaimAfterReviewPeriod() public {
        uint256 jobId = _createAcceptAndSubmitJob();

        vm.warp(block.timestamp + reviewPeriod);

        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);

        vm.prank(client);
        marketplace.claimAfterReviewPeriod(jobId);
    }

    function test_RevertIf_StrangerTriesToClaimAfterReviewPeriod() public {
        uint256 jobId = _createAcceptAndSubmitJob();

        vm.warp(block.timestamp + reviewPeriod);

        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);

        vm.prank(stranger);
        marketplace.claimAfterReviewPeriod(jobId);
    }

    function test_RevertIf_JobIsNotSubmittedForClaim() public {
        uint256 jobId = _createAndAcceptJob();

        vm.warp(block.timestamp + reviewPeriod);

        vm.expectRevert(EscrowMarketplace.InvalidJobStatus.selector);

        vm.prank(freelancer);
        marketplace.claimAfterReviewPeriod(jobId);
    }

    function test_RevertIf_DisputedJobIsClaimedAfterReviewPeriod() public {
        uint256 jobId = _createAcceptAndSubmitJob();

        vm.prank(client);
        marketplace.openDispute(jobId, disputeReasonURI);

        vm.warp(block.timestamp + reviewPeriod);

        vm.expectRevert(EscrowMarketplace.InvalidJobStatus.selector);

        vm.prank(freelancer);
        marketplace.claimAfterReviewPeriod(jobId);
    }

    function test_RevertIf_CompletedJobIsClaimedAfterReviewPeriod() public {
        uint256 jobId = _createAcceptAndSubmitJob();

        vm.prank(client);
        marketplace.approveWork(jobId);

        vm.warp(block.timestamp + reviewPeriod);

        vm.expectRevert(EscrowMarketplace.InvalidJobStatus.selector);

        vm.prank(freelancer);
        marketplace.claimAfterReviewPeriod(jobId);
    }

    function test_RevertIf_ClaimAfterReviewPeriodIsCalledTwice() public {
        uint256 jobId = _createAcceptAndSubmitJob();

        vm.warp(block.timestamp + reviewPeriod);

        vm.prank(freelancer);
        marketplace.claimAfterReviewPeriod(jobId);

        vm.expectRevert(EscrowMarketplace.InvalidJobStatus.selector);

        vm.prank(freelancer);
        marketplace.claimAfterReviewPeriod(jobId);
    }

    function test_ClaimAfterReviewPeriod_EmitsPaymentClaimedAfterReviewEvent() public {
        uint256 jobId = _createAcceptAndSubmitJob();

        vm.warp(block.timestamp + reviewPeriod);

        vm.expectEmit(true, true, false, true);
        emit PaymentClaimedAfterReview(jobId, freelancer);

        vm.prank(freelancer);
        marketplace.claimAfterReviewPeriod(jobId);
    }

    function test_ClaimAfterReviewPeriod_EmitsPaymentReleasedEvent() public {
        uint256 expectedFee =
            (amount * platformFeeBps) / marketplace.BPS_DENOMINATOR();

        uint256 expectedFreelancerAmount = amount - expectedFee;

        uint256 jobId = _createAcceptAndSubmitJob();

        vm.warp(block.timestamp + reviewPeriod);

        vm.expectEmit(true, true, false, true);

        emit PaymentReleased(
            jobId,
            freelancer,
            expectedFreelancerAmount,
            expectedFee
        );

        vm.prank(freelancer);
        marketplace.claimAfterReviewPeriod(jobId);
    }

    function test_RevertIf_ClaimedJobDoesNotExist() public {
        vm.expectRevert(EscrowMarketplace.JobDoesNotExist.selector);

        vm.prank(freelancer);
        marketplace.claimAfterReviewPeriod(1);
    }

    function test_RevertIf_ClaimedJobIdIsZero() public {
        vm.expectRevert(EscrowMarketplace.JobDoesNotExist.selector);

        vm.prank(freelancer);
        marketplace.claimAfterReviewPeriod(0);
    }

    ///////////////////////////////////////////
    // Pause/Unpause Tests
    ///////////////////////////////////////////

    function test_OwnerCanPauseMarketplace() public {
        marketplace.pause();

        assertEq(marketplace.paused(), true);
    }

    function test_PauseMarketplace_EmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit MarketPlacePaused(address(this));

        marketplace.pause();
    }

    function test_RevertIf_ClientPausesMarketplace() public {
        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);

        vm.prank(client);
        marketplace.pause();
    }

    function test_RevertIf_FreelancerPausesMarketplace() public {
        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);

        vm.prank(freelancer);
        marketplace.pause();
    }

    function test_RevertIf_StrangerPausesMarketplace() public {
        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);

        vm.prank(stranger);
        marketplace.pause();
    }

    function test_RevertIf_PauseMarketplaceTwice() public {
        marketplace.pause();

        vm.expectRevert(EscrowMarketplace.MarketPlaceIsPaused.selector);

        marketplace.pause();
    }

    function test_OwnerCanUnpauseMarketplace() public {
        marketplace.pause();
        marketplace.unpause();

        assertEq(marketplace.paused(), false);
    }

    function test_UnpauseMarketplace_EmitsEvent() public {
        marketplace.pause();

        vm.expectEmit(true, false, false, false);
        emit MarketPlaceUnpaused(address(this));

        marketplace.unpause();
    }

    function test_RevertIf_ClientUnpausesMarketplace() public {
        marketplace.pause();

        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);

        vm.prank(client);
        marketplace.unpause();
    }

    function test_RevertIf_UnpauseMarketplaceWhenNotPaused() public {
        vm.expectRevert(EscrowMarketplace.MarketPlaceNotPaused.selector);

        marketplace.unpause();
    }

    function test_RevertIf_CreateJobWhenPaused() public {
        marketplace.pause();

        vm.startPrank(client);
        token.approve(address(marketplace), amount);

        vm.expectRevert(EscrowMarketplace.MarketPlaceIsPaused.selector);

        marketplace.createJob({
            freelancer: freelancer,
            token: address(token),
            amount: amount,
            deadline: deadline,
            metadataURI: metadataURI
        });
        vm.stopPrank();
    }

    function test_RevertIf_AcceptJobWhenPaused() public {
        uint256 jobId = _createJob();

        marketplace.pause();

        vm.expectRevert(EscrowMarketplace.MarketPlaceIsPaused.selector);

        vm.prank(freelancer);
        marketplace.acceptJob(jobId);
    }

    function test_RevertIf_SubmitWorkWhenPaused() public {
        uint256 jobId = _createAndAcceptJob();

        marketplace.pause();

        vm.expectRevert(EscrowMarketplace.MarketPlaceIsPaused.selector);

        vm.prank(freelancer);
        marketplace.submitWork(jobId, deliveryURI);
    }

    function test_RevertIf_ApproveWorkWhenPaused() public {
        uint256 jobId = _createAcceptAndSubmitJob();

        marketplace.pause();

        vm.expectRevert(EscrowMarketplace.MarketPlaceIsPaused.selector);

        vm.prank(client);
        marketplace.approveWork(jobId);
    }

    function test_RevertIf_CancelJobWhenPaused() public {
        uint256 jobId = _createJob();

        marketplace.pause();

        vm.expectRevert(EscrowMarketplace.MarketPlaceIsPaused.selector);

        vm.prank(client);
        marketplace.cancelJob(jobId);
    }

    function test_RevertIf_CancelExpiredJobWhenPaused() public {
        uint256 jobId = _createAndAcceptJob();

        vm.warp(deadline + 1);

        marketplace.pause();

        vm.expectRevert(EscrowMarketplace.MarketPlaceIsPaused.selector);

        vm.prank(client);
        marketplace.cancelExpiredJob(jobId);
    }

    function test_RevertIf_OpenDisputeWhenPaused() public {
        uint256 jobId = _createAndAcceptJob();

        marketplace.pause();

        vm.expectRevert(EscrowMarketplace.MarketPlaceIsPaused.selector);

        vm.prank(client);
        marketplace.openDispute(jobId, disputeReasonURI);
    }

    function test_RevertIf_ResolveDisputeWhenPaused() public {
        uint256 jobId = _createAcceptSubmitAndDisputeJob();

        marketplace.pause();

        vm.expectRevert(EscrowMarketplace.MarketPlaceIsPaused.selector);

        vm.prank(arbitrator);
        marketplace.resolveDispute(jobId, amount, 0);
    }

    function test_RevertIf_ClaimAfterReviewPeriodWhenPaused() public {
        uint256 jobId = _createAcceptAndSubmitJob();

        vm.warp(block.timestamp + reviewPeriod);

        marketplace.pause();

        vm.expectRevert(EscrowMarketplace.MarketPlaceIsPaused.selector);

        vm.prank(freelancer);
        marketplace.claimAfterReviewPeriod(jobId);
    }

    ///////////////////////////////////////////////////////////////
    // Set new FeeRecipient, PlatformFee, Arbitrator, ReviewPeriod
    ///////////////////////////////////////////////////////////////

    function test_OwnerCanSetFeeRecipient() public {
        address newFeeRecipient = address(6);

        vm.prank(address(this));
        marketplace.setFeeRecipient(newFeeRecipient);

        assertEq(marketplace.feeRecipient(), newFeeRecipient);
    }

    function test_SetFeeRecipient_EmitsEvent() public {
        address newFeeRecipient = makeAddr("newFeeRecipient");

        vm.expectEmit(true, true, false, true);
        emit FeeRecipientUpdated(feeRecipient, newFeeRecipient);

        marketplace.setFeeRecipient(newFeeRecipient);
    }

    function test_RevertIf_NonOwnerSetsFeeRecipient() public {
        address newFeeRecipient = makeAddr("newFeeRecipient");

        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);

        vm.prank(client);
        marketplace.setFeeRecipient(newFeeRecipient);
    }

    function test_RevertIf_SetFeeRecipientToZeroAddress() public {
        vm.expectRevert(EscrowMarketplace.InvalidAddress.selector);

        marketplace.setFeeRecipient(address(0));
    }

    function test_OwnerCanSetPlatformFee() public {
        uint256 newFeeBps = 300;

        marketplace.setPlatformFee(newFeeBps);

        assertEq(marketplace.platformFeeBps(), newFeeBps);
    }

    function test_SetPlatformFee_EmitsEvent() public {
        uint256 newFeeBps = 300;

        vm.expectEmit(false, false, false, true);
        emit PlatformFeeUpdated(platformFeeBps, newFeeBps);

        marketplace.setPlatformFee(newFeeBps);
    }

    function test_RevertIf_NonOwnerSetsPlatformFee() public {
        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);

        vm.prank(client);
        marketplace.setPlatformFee(300);
    }

    function test_RevertIf_PlatformFeeIsTooHighWhenUpdated() public {
        uint256 tooHighFee = marketplace.BPS_DENOMINATOR() + 1;

        vm.expectRevert(EscrowMarketplace.InvalidFee.selector);

        marketplace.setPlatformFee(tooHighFee);
    }

    function test_OwnerCanSetPlatformFeeToZero() public {
        marketplace.setPlatformFee(0);

        assertEq(marketplace.platformFeeBps(), 0);
    }

    function test_OwnerCanSetArbitrator() public {
        address newArbitrator = makeAddr("newArbitrator");

        marketplace.setArbitrator(newArbitrator);

        assertEq(marketplace.arbitrator(), newArbitrator);
    }

    function test_SetArbitrator_EmitsEvent() public {
        address newArbitrator = makeAddr("newArbitrator");

        vm.expectEmit(true, true, false, true);
        emit ArbitratorUpdated(arbitrator, newArbitrator);

        marketplace.setArbitrator(newArbitrator);
    }

    function test_RevertIf_NonOwnerSetsArbitrator() public {
        address newArbitrator = makeAddr("newArbitrator");

        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);

        vm.prank(client);
        marketplace.setArbitrator(newArbitrator);
    }

    function test_RevertIf_ArbitratorIsZeroAddressWhenUpdated() public {
        vm.expectRevert(EscrowMarketplace.InvalidAddress.selector);

        marketplace.setArbitrator(address(0));
    }       

    function test_OwnerCanSetReviewPeriod() public {
        uint256 newReviewPeriod = 7 days;

        marketplace.setReviewPeriod(newReviewPeriod);

        assertEq(marketplace.reviewPeriod(), newReviewPeriod);
    }

    function test_SetReviewPeriod_EmitsEvent() public {
        uint256 newReviewPeriod = 7 days;

        vm.expectEmit(false, false, false, true);
        emit ReviewPeriodUpdated(reviewPeriod, newReviewPeriod);

        marketplace.setReviewPeriod(newReviewPeriod);
    }

    function test_RevertIf_NonOwnerSetsReviewPeriod() public {
        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);

        vm.prank(client);
        marketplace.setReviewPeriod(7 days);
    }

    function test_RevertIf_ReviewPeriodIsZeroWhenUpdated() public {
        vm.expectRevert(EscrowMarketplace.InvalidReviewPeriod.selector);

        marketplace.setReviewPeriod(0);
    }

    ///////////////////////////////////////////////////////////////
    //                      Acounting
    ///////////////////////////////////////////////////////////////

    function test_CreateJob_IncreasesTotalEscrowed() public {
        uint256 jobAmount = 100 ether;

        vm.startPrank(client);
        token.approve(address(marketplace), jobAmount);
        uint256 jobId = marketplace.createJob(
            freelancer,
            address(token),
            jobAmount,
            block.timestamp + 1 days,
            "ipfs://job"
        );
        vm.stopPrank();

        assertEq(jobId, 1);
        assertEq(
            marketplace.totalEscrowed(address(token)),
            jobAmount
        );
    }

    function test_CreateMultipleJobs_AccumulatesTotalEscrowed() public {
        uint256 firstAmount = 100 ether;
        uint256 secondAmount = 200 ether;

        vm.startPrank(client);

        token.approve(address(marketplace), firstAmount + secondAmount);

        marketplace.createJob(
            freelancer,
            address(token),
            firstAmount,
            block.timestamp + 1 days,
            "ipfs://job1"
        );

        marketplace.createJob(
            freelancer,
            address(token),
            secondAmount,
            block.timestamp + 1 days,
            "ipfs://job2"
        );

        vm.stopPrank();

        assertEq(
            marketplace.totalEscrowed(address(token)),
            firstAmount + secondAmount
        );
    }

    function test_ApproveWork_DecreasesTotalEscrowed() public {
        uint256 jobAmount = 100 ether;

        vm.startPrank(client);
        token.approve(address(marketplace), jobAmount);
        uint256 jobId = marketplace.createJob(
            freelancer,
            address(token),
            jobAmount,
            block.timestamp + 1 days,
            "ipfs://job"
        );
        vm.stopPrank();

        vm.prank(freelancer);
        marketplace.acceptJob(jobId);

        vm.prank(freelancer);
        marketplace.submitWork(jobId, "ipfs://work");

        vm.prank(client);
        marketplace.approveWork(jobId);

        assertEq(
            marketplace.totalEscrowed(address(token)),
            0
        );
    }

    function test_CancelJob_DecreasesTotalEscrowed() public {
        uint256 jobAmount = 100 ether;

        vm.startPrank(client);
        token.approve(address(marketplace), jobAmount);
        uint256 jobId = marketplace.createJob(
            freelancer,
            address(token),
            jobAmount,
            block.timestamp + 1 days,
            "ipfs://job"
        );
        vm.stopPrank();

        vm.prank(client);
        marketplace.cancelJob(jobId);

        assertEq(
            marketplace.totalEscrowed(address(token)),
            0
        );
    }

    function test_CancelExpiredJob_DecreasesTotalEscrowed() public {
        uint256 jobAmount = 100 ether;

        vm.startPrank(client);
        token.approve(address(marketplace), jobAmount);
        uint256 jobId = marketplace.createJob(
            freelancer,
            address(token),
            jobAmount,
            block.timestamp + 1 days,
            "ipfs://job"
        );
        vm.stopPrank();

        vm.prank(freelancer);
        marketplace.acceptJob(jobId);

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(client);
        marketplace.cancelExpiredJob(jobId);

        assertEq(
            marketplace.totalEscrowed(address(token)),
            0
        );
    }

    function test_ResolveDispute_DecreasesTotalEscrowed() public {
        uint256 jobAmount = 100 ether;

        vm.startPrank(client);
        token.approve(address(marketplace), jobAmount);
        uint256 jobId = marketplace.createJob(
            freelancer,
            address(token),
            jobAmount,
            block.timestamp + 1 days,
            "ipfs://job"
        );
        vm.stopPrank();

        vm.prank(freelancer);
        marketplace.acceptJob(jobId);

        vm.prank(freelancer);
        marketplace.submitWork(jobId, "ipfs://work");

        vm.prank(client);
        marketplace.openDispute(jobId, "ipfs://dispute");

        uint256 clientAmount = 40 ether;
        uint256 freelancerAmount = 60 ether;

        vm.prank(arbitrator);
        marketplace.resolveDispute(
            jobId,
            clientAmount,
            freelancerAmount
        );

        assertEq(
            marketplace.totalEscrowed(address(token)),
            0
        );
    }

    function test_ClaimAfterReviewPeriod_DecreasesTotalEscrowed() public {
        uint256 jobAmount = 100 ether;

        vm.startPrank(client);
        token.approve(address(marketplace), jobAmount);
        uint256 jobId = marketplace.createJob(
            freelancer,
            address(token),
            jobAmount,
            block.timestamp + 1 days,
            "ipfs://job"
        );
        vm.stopPrank();

        vm.prank(freelancer);
        marketplace.acceptJob(jobId);

        vm.prank(freelancer);
        marketplace.submitWork(jobId, "ipfs://work");

        vm.warp(block.timestamp + reviewPeriod + 1);

        vm.prank(freelancer);
        marketplace.claimAfterReviewPeriod(jobId);

        assertEq(
            marketplace.totalEscrowed(address(token)),
            0
        );
    }

    ///////////////////////////////////////////////////////////////
    //                     RecoverERC20
    ///////////////////////////////////////////////////////////////

    function test_OwnerCanRecoverERC20() public {
        uint256 recoverAmount = 100 ether;

        token.mint(address(marketplace), recoverAmount);

        uint256 recipientBalanceBefore = token.balanceOf(recipient);

        marketplace.recoverERC20(
            address(token),
            recoverAmount,
            recipient
        );

        assertEq(
            token.balanceOf(recipient),
            recipientBalanceBefore + recoverAmount
        );

        assertEq(
            token.balanceOf(address(marketplace)),
            0
        );
    }

    function test_RecoverERC20_EmitsEvent() public {
        uint256 recoverAmount = 100 ether;

        token.mint(address(marketplace), recoverAmount);

        vm.expectEmit(true, true, false, true);
        emit ERC20Recovered(
            address(token),
            recoverAmount,
            recipient
        );

        marketplace.recoverERC20(
            address(token),
            recoverAmount,
            recipient
        );
    }

    function test_RevertIf_NonOwnerRecoversERC20() public {
        uint256 recoverAmount = 100 ether;

        token.mint(address(marketplace), recoverAmount);

        vm.prank(client);

        vm.expectRevert(
            EscrowMarketplace.Unauthorized.selector
        );

        marketplace.recoverERC20(
            address(token),
            recoverAmount,
            recipient
        );
    }

    function test_RevertIf_RecoverERC20TokenIsZeroAddress() public {
        vm.expectRevert(
            EscrowMarketplace.InvalidAddress.selector
        );

        marketplace.recoverERC20(
            address(0),
            100 ether,
            recipient
        );
    }

    function test_RevertIf_RecoverERC20RecipientIsZeroAddress() public {
        token.mint(address(marketplace), 100 ether);

        vm.expectRevert(
            EscrowMarketplace.InvalidAddress.selector
        );

        marketplace.recoverERC20(
            address(token),
            100 ether,
            address(0)
        );
    }

    function test_RevertIf_RecoverERC20AmountIsZero() public {
        vm.expectRevert(
            EscrowMarketplace.InvalidAmount.selector
        );

        marketplace.recoverERC20(
            address(token),
            0,
            recipient
        );
    }

    function test_RevertIf_RecoverERC20ExceedsRecoverableBalance() public {
        uint256 escrowAmount = 100 ether;
        uint256 accidentalAmount = 50 ether;

        vm.startPrank(client);
        token.approve(address(marketplace), escrowAmount);
        marketplace.createJob(
            freelancer,
            address(token),
            escrowAmount,
            block.timestamp + 1 days,
            "ipfs://job"
        );
        vm.stopPrank();

        token.mint(
            address(marketplace),
            accidentalAmount
        );

        assertEq(
            token.balanceOf(address(marketplace)),
            escrowAmount + accidentalAmount
        );

        assertEq(
            marketplace.totalEscrowed(address(token)),
            escrowAmount
        );

        vm.expectRevert(
            EscrowMarketplace.InsufficientRecoverableBalance.selector
        );

        marketplace.recoverERC20(
            address(token),
            accidentalAmount + 1,
            recipient
        );
    }

    function test_RecoverERC20_DoesNotTouchEscrowedFunds() public {
        uint256 escrowAmount = 100 ether;
        uint256 accidentalAmount = 50 ether;

        vm.startPrank(client);
        token.approve(address(marketplace), escrowAmount);
        marketplace.createJob(
            freelancer,
            address(token),
            escrowAmount,
            block.timestamp + 1 days,
            "ipfs://job"
        );
        vm.stopPrank();

        token.mint(
            address(marketplace),
            accidentalAmount
        );

        marketplace.recoverERC20(
            address(token),
            accidentalAmount,
            recipient
        );

        assertEq(
            token.balanceOf(address(marketplace)),
            escrowAmount
        );

        assertEq(
            marketplace.totalEscrowed(address(token)),
            escrowAmount
        );
    }

    function test_RecoverERC20_CanRecoverOnlySurplus() public {
        uint256 escrowAmount = 100 ether;
        uint256 accidentalAmount = 50 ether;

        vm.startPrank(client);
        token.approve(address(marketplace), escrowAmount);
        marketplace.createJob(
            freelancer,
            address(token),
            escrowAmount,
            block.timestamp + 1 days,
            "ipfs://job"
        );
        vm.stopPrank();

        token.mint(
            address(marketplace),
            accidentalAmount
        );

        marketplace.recoverERC20(
            address(token),
            accidentalAmount,
            recipient
        );

        assertEq(
            token.balanceOf(address(marketplace)),
            escrowAmount
        );

        assertEq(
            marketplace.totalEscrowed(address(token)),
            escrowAmount
        );

        assertEq(
            token.balanceOf(recipient),
            accidentalAmount
        );
    }
}
