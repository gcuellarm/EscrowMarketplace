// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EscrowMarketplace} from "../src/EscrowMarketplace.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract EscrowMarketplaceFuzzTest is Test {
    EscrowMarketplace marketplace;
    MockERC20 token;

    address client = makeAddr("client");
    address freelancer = makeAddr("freelancer");
    address feeRecipient = makeAddr("feeRecipient");
    address arbitrator = makeAddr("arbitrator");
    address stranger = makeAddr("stranger");

    uint256 constant amount = 1_000 ether;
    uint256 constant platformFeeBps = 500;
    uint256 constant reviewPeriod = 3 days;
    uint256 deadline;

    string metadataURI = "ipfs://job-metadata";
    string deliveryURI = "ipfs://delivery";
    string disputeReasonURI = "ipfs://dispute";

    function setUp() public {
        marketplace = new EscrowMarketplace(feeRecipient, platformFeeBps, arbitrator, reviewPeriod);
        token = new MockERC20();
        deadline = block.timestamp + 7 days;
    }

    function _createJob() internal returns (uint256 jobId) {
        token.mint(client, amount);
        vm.startPrank(client);
        token.approve(address(marketplace), amount);
        jobId = marketplace.createJob(freelancer, address(token), amount, deadline, metadataURI);
        vm.stopPrank();
    }

    function _createAcceptSubmitAndDisputeJob() internal returns (uint256 jobId) {
        jobId = _createJob();
        vm.prank(freelancer);
        marketplace.acceptJob(jobId);
        vm.prank(freelancer);
        marketplace.submitWork(jobId, deliveryURI);
        vm.prank(client);
        marketplace.openDispute(jobId, disputeReasonURI);
    }

    function testFuzz_CreateJob_WithValidAmount(uint256 rawAmount) public {
        uint256 fuzzAmount = bound(rawAmount, 1, 1_000_000 ether);
        token.mint(client, fuzzAmount);
        vm.startPrank(client);
        token.approve(address(marketplace), fuzzAmount);
        uint256 jobId = marketplace.createJob(freelancer, address(token), fuzzAmount, deadline, metadataURI);
        vm.stopPrank();
        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);
        assertEq(job.client, client);
        assertEq(job.freelancer, freelancer);
        assertEq(job.token, address(token));
        assertEq(job.amount, fuzzAmount);
        assertEq(uint256(job.status), uint256(EscrowMarketplace.JobStatus.Funded));
        assertEq(token.balanceOf(client), 0);
        assertEq(token.balanceOf(address(marketplace)), fuzzAmount);
        assertEq(marketplace.totalEscrowed(address(token)), fuzzAmount);
    }

    function testFuzz_ResolveDispute_DistributesCorrectly(uint256 rawClientAmount) public {
        uint256 jobId = _createAcceptSubmitAndDisputeJob();
        uint256 clientAmount = bound(rawClientAmount, 0, amount);
        uint256 freelancerAmount = amount - clientAmount;
        uint256 expectedFee = (freelancerAmount * platformFeeBps) / marketplace.BPS_DENOMINATOR();
        uint256 expectedFreelancerAmount = freelancerAmount - expectedFee;
        vm.prank(arbitrator);
        marketplace.resolveDispute(jobId, clientAmount, freelancerAmount);
        assertEq(token.balanceOf(client), clientAmount);
        assertEq(token.balanceOf(freelancer), expectedFreelancerAmount);
        assertEq(token.balanceOf(feeRecipient), expectedFee);
        assertEq(token.balanceOf(client) + token.balanceOf(freelancer) + token.balanceOf(feeRecipient), amount);
        assertEq(token.balanceOf(address(marketplace)), 0);
        assertEq(marketplace.totalEscrowed(address(token)), 0);
        assertEq(uint256(marketplace.getJob(jobId).status), uint256(EscrowMarketplace.JobStatus.Completed));
    }

    function testFuzz_RecoverERC20_OnlyRecoversSurplus(uint256 rawSurplus) public {
        uint256 surplus = bound(rawSurplus, 1, 1_000_000 ether);
        _createJob();
        token.mint(address(marketplace), surplus);
        address recipient = makeAddr("recipient");
        marketplace.recoverERC20(address(token), surplus, recipient);
        assertEq(token.balanceOf(recipient), surplus);
        assertEq(token.balanceOf(address(marketplace)), amount);
        assertEq(marketplace.totalEscrowed(address(token)), amount);
    }

    function testFuzz_CreateETHJob(uint256 rawAmount) public {
        uint256 ethAmount = bound(rawAmount, 1 wei, 100 ether);
        vm.deal(client, ethAmount);
        vm.prank(client);
        uint256 jobId =
            marketplace.createJob{value: ethAmount}(freelancer, address(0), ethAmount, deadline, metadataURI);
        EscrowMarketplace.Job memory job = marketplace.getJob(jobId);
        assertEq(job.amount, ethAmount);
        assertEq(marketplace.totalEscrowed(address(0)), ethAmount);
        assertEq(address(marketplace).balance, ethAmount);
        assertEq(client.balance, 0);
    }

    function testFuzz_RevertIf_ETHAmountDoesNotMatch(uint256 rawAmount, uint256 rawSent) public {
        uint256 expectedAmount = bound(rawAmount, 1 wei, 100 ether);
        uint256 sentAmount = bound(rawSent, 0, 100 ether);
        vm.assume(sentAmount != expectedAmount);
        vm.deal(client, sentAmount);
        vm.prank(client);
        vm.expectRevert(EscrowMarketplace.InvalidETHAmount.selector);
        marketplace.createJob{value: sentAmount}(freelancer, address(0), expectedAmount, deadline, metadataURI);
        assertEq(address(marketplace).balance, 0);
        assertEq(marketplace.totalEscrowed(address(0)), 0);
        assertEq(marketplace.nextJobId(), 1);
    }

    function testFuzz_ValidPlatformFee(uint256 rawFee) public {
        uint256 fuzzFee = bound(rawFee, 0, 10_000);
        EscrowMarketplace fuzzMarketplace = new EscrowMarketplace(feeRecipient, fuzzFee, arbitrator, reviewPeriod);
        assertEq(fuzzMarketplace.platformFeeBps(), fuzzFee);
    }

    function testFuzz_RevertIf_PlatformFeeAboveMaximum(uint256 rawFee) public {
        uint256 invalidFee = bound(rawFee, 10_001, type(uint16).max);
        vm.expectRevert(EscrowMarketplace.InvalidFee.selector);
        new EscrowMarketplace(feeRecipient, invalidFee, arbitrator, reviewPeriod);
    }

    function testFuzz_ResolveDispute_RevertsForInvalidAllocation(uint256 rawClientAmount, uint256 rawFreelancerAmount)
        public
    {
        uint256 jobId = _createAcceptSubmitAndDisputeJob();
        uint256 clientAmount = bound(rawClientAmount, 0, amount);
        uint256 freelancerAmount = bound(rawFreelancerAmount, 0, amount);
        vm.assume(freelancerAmount != amount - clientAmount);

        vm.prank(arbitrator);
        vm.expectRevert(EscrowMarketplace.InvalidResolutionAmounts.selector);
        marketplace.resolveDispute(jobId, clientAmount, freelancerAmount);

        assertEq(token.balanceOf(address(marketplace)), amount);
        assertEq(marketplace.totalEscrowed(address(token)), amount);
        assertEq(uint256(marketplace.getJob(jobId).status), uint256(EscrowMarketplace.JobStatus.Disputed));
    }

    function testFuzz_RecoverERC20_RevertsAboveSurplus(uint256 rawSurplus, uint256 rawExcess) public {
        uint256 surplus = bound(rawSurplus, 0, 1_000_000 ether);
        uint256 excess = bound(rawExcess, 1, 1_000_000 ether);
        _createJob();
        token.mint(address(marketplace), surplus);

        vm.expectRevert(EscrowMarketplace.InsufficientRecoverableBalance.selector);
        marketplace.recoverERC20(address(token), surplus + excess, stranger);

        assertEq(token.balanceOf(address(marketplace)), amount + surplus);
        assertEq(marketplace.totalEscrowed(address(token)), amount);
    }

    function testFuzz_CreateERC20Job_RevertsWhenETHIsSent(uint256 rawSent) public {
        uint256 sentAmount = bound(rawSent, 1 wei, 100 ether);
        token.mint(client, amount);
        vm.deal(client, sentAmount);

        vm.startPrank(client);
        token.approve(address(marketplace), amount);
        vm.expectRevert(EscrowMarketplace.InvalidETHAmount.selector);
        marketplace.createJob{value: sentAmount}(freelancer, address(token), amount, deadline, metadataURI);
        vm.stopPrank();

        assertEq(token.balanceOf(client), amount);
        assertEq(token.balanceOf(address(marketplace)), 0);
        assertEq(marketplace.totalEscrowed(address(token)), 0);
        assertEq(marketplace.nextJobId(), 1);
    }
}
