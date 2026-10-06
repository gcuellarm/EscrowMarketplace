// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EscrowMarketplace} from "../src/EscrowMarketplace.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract RejectingETHActor {
    function createETHJob(
        EscrowMarketplace marketplace,
        address freelancer,
        uint256 amount,
        uint256 deadline
    ) external returns (uint256) {
        return marketplace.createJob{value: amount}(
            freelancer,
            address(0),
            amount,
            deadline,
            "ipfs://metadata"
        );
    }

    function acceptJob(EscrowMarketplace marketplace, uint256 jobId) external {
        marketplace.acceptJob(jobId);
    }

    function submitWork(EscrowMarketplace marketplace, uint256 jobId) external {
        marketplace.submitWork(jobId, "ipfs://delivery");
    }

    function cancelJob(EscrowMarketplace marketplace, uint256 jobId) external {
        marketplace.cancelJob(jobId);
    }
}

contract EscrowMarketplaceEdgeCasesTest is Test {
    EscrowMarketplace internal marketplace;
    MockERC20 internal token;

    address internal client = makeAddr("edge-client");
    address internal freelancer = makeAddr("edge-freelancer");
    address internal feeRecipient = makeAddr("edge-fee-recipient");
    address internal arbitrator = makeAddr("edge-arbitrator");

    uint256 internal constant AMOUNT = 1_000 ether;
    uint256 internal constant REVIEW_PERIOD = 3 days;
    uint256 internal deadline;

    function setUp() public {
        marketplace = new EscrowMarketplace(feeRecipient, 500, arbitrator, REVIEW_PERIOD);
        token = new MockERC20();
        deadline = block.timestamp + 7 days;
    }

    function test_OneUnitPaymentRoundsFeeDownToZero() public {
        marketplace.setPlatformFee(9_999);
        uint256 jobId = _createERC20Job(1);
        _acceptAndSubmit(jobId, freelancer);

        vm.prank(client);
        marketplace.approveWork(jobId);

        assertEq(token.balanceOf(freelancer), 1);
        assertEq(token.balanceOf(feeRecipient), 0);
        assertEq(marketplace.totalEscrowed(address(token)), 0);
    }

    function test_MaximumFeeSendsEntireFreelancerAllocationToFeeRecipient() public {
        marketplace.setPlatformFee(marketplace.BPS_DENOMINATOR());
        uint256 jobId = _createERC20Job(AMOUNT);
        _acceptAndSubmit(jobId, freelancer);

        vm.prank(client);
        marketplace.approveWork(jobId);

        assertEq(token.balanceOf(freelancer), 0);
        assertEq(token.balanceOf(feeRecipient), AMOUNT);
        assertEq(token.balanceOf(address(marketplace)), 0);
    }

    function test_FeeConfigurationAtSettlementAppliesToExistingJob() public {
        uint256 jobId = _createERC20Job(AMOUNT);
        _acceptAndSubmit(jobId, freelancer);
        address newFeeRecipient = makeAddr("new-fee-recipient");
        marketplace.setPlatformFee(1_000);
        marketplace.setFeeRecipient(newFeeRecipient);

        vm.prank(client);
        marketplace.approveWork(jobId);

        assertEq(token.balanceOf(freelancer), 900 ether);
        assertEq(token.balanceOf(feeRecipient), 0);
        assertEq(token.balanceOf(newFeeRecipient), 100 ether);
    }

    function test_UpdatedArbitratorImmediatelyControlsExistingDispute() public {
        uint256 jobId = _createERC20Job(AMOUNT);
        _acceptAndSubmit(jobId, freelancer);
        vm.prank(client);
        marketplace.openDispute(jobId, "ipfs://reason");
        address newArbitrator = makeAddr("new-arbitrator");
        marketplace.setArbitrator(newArbitrator);

        vm.prank(arbitrator);
        vm.expectRevert(EscrowMarketplace.Unauthorized.selector);
        marketplace.resolveDispute(jobId, AMOUNT, 0);

        vm.prank(newArbitrator);
        marketplace.resolveDispute(jobId, AMOUNT, 0);

        assertEq(token.balanceOf(client), AMOUNT);
        assertEq(uint256(marketplace.getJob(jobId).status), uint256(EscrowMarketplace.JobStatus.Completed));
    }

    function test_ReviewPeriodUpdateAppliesToAlreadySubmittedJob() public {
        uint256 jobId = _createERC20Job(AMOUNT);
        _acceptAndSubmit(jobId, freelancer);
        marketplace.setReviewPeriod(10 days);
        vm.warp(block.timestamp + REVIEW_PERIOD);

        vm.prank(freelancer);
        vm.expectRevert(EscrowMarketplace.ReviewPeriodNotPassed.selector);
        marketplace.claimAfterReviewPeriod(jobId);

        vm.warp(marketplace.getJob(jobId).submittedAt + 10 days);
        vm.prank(freelancer);
        marketplace.claimAfterReviewPeriod(jobId);
    }

    function test_ApproveETHRollsBackStateWhenFreelancerRejectsPayment() public {
        RejectingETHActor rejectingFreelancer = new RejectingETHActor();
        vm.deal(client, AMOUNT);
        vm.prank(client);
        uint256 jobId = marketplace.createJob{value: AMOUNT}(
            address(rejectingFreelancer), address(0), AMOUNT, deadline, "ipfs://metadata"
        );
        rejectingFreelancer.acceptJob(marketplace, jobId);
        rejectingFreelancer.submitWork(marketplace, jobId);

        vm.prank(client);
        vm.expectRevert(EscrowMarketplace.ETHTransferFailed.selector);
        marketplace.approveWork(jobId);

        assertEq(uint256(marketplace.getJob(jobId).status), uint256(EscrowMarketplace.JobStatus.Submitted));
        assertEq(marketplace.totalEscrowed(address(0)), AMOUNT);
        assertEq(address(marketplace).balance, AMOUNT);
    }

    function test_CancelETHRollsBackStateWhenClientRejectsRefund() public {
        RejectingETHActor rejectingClient = new RejectingETHActor();
        vm.deal(address(rejectingClient), AMOUNT);
        uint256 jobId = rejectingClient.createETHJob(marketplace, freelancer, AMOUNT, deadline);

        vm.expectRevert(EscrowMarketplace.ETHTransferFailed.selector);
        rejectingClient.cancelJob(marketplace, jobId);

        assertEq(uint256(marketplace.getJob(jobId).status), uint256(EscrowMarketplace.JobStatus.Funded));
        assertEq(marketplace.totalEscrowed(address(0)), AMOUNT);
        assertEq(address(marketplace).balance, AMOUNT);
    }

    function test_ResolutionRejectsClientAmountAboveEscrowWithoutArithmeticPanic() public {
        uint256 jobId = _createERC20Job(AMOUNT);
        _acceptAndSubmit(jobId, freelancer);
        vm.prank(client);
        marketplace.openDispute(jobId, "ipfs://reason");

        vm.prank(arbitrator);
        vm.expectRevert(EscrowMarketplace.InvalidResolutionAmounts.selector);
        marketplace.resolveDispute(jobId, AMOUNT + 1, 0);

        assertEq(uint256(marketplace.getJob(jobId).status), uint256(EscrowMarketplace.JobStatus.Disputed));
        assertEq(marketplace.totalEscrowed(address(token)), AMOUNT);
    }

    function _createERC20Job(uint256 jobAmount) internal returns (uint256 jobId) {
        token.mint(client, jobAmount);
        vm.startPrank(client);
        token.approve(address(marketplace), jobAmount);
        jobId = marketplace.createJob(freelancer, address(token), jobAmount, deadline, "ipfs://metadata");
        vm.stopPrank();
    }

    function _acceptAndSubmit(uint256 jobId, address assignedFreelancer) internal {
        vm.prank(assignedFreelancer);
        marketplace.acceptJob(jobId);
        vm.prank(assignedFreelancer);
        marketplace.submitWork(jobId, "ipfs://delivery");
    }
}
