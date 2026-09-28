// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol"; 
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract EscrowMarketplace is ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum JobStatus {
        Created,
        Funded,
        InProgress,
        Submitted,
        Approved,
        Disputed,
        Cancelled,
        Completed
    }

    struct Job {
        address client;
        address freelancer;
        address token;
        uint256 amount;
        uint256 deadline;
        uint256 submittedAt;
        JobStatus status;
        string metadataURI;
        string deliveryURI;
        string disputeReasonURI;
    }

    uint256 public nextJobId;

    uint256 public constant BPS_DENOMINATOR = 10_000;

    uint256 public platformFeeBps;
    address public feeRecipient;
    address public arbitrator;
    uint256 public reviewPeriod;
    address public owner;
    bool public paused;

    mapping(uint256 => Job) private jobs;

    mapping(address => uint256) public totalEscrowed;


    error InvalidAddress();
    error InvalidAmount();
    error InvalidDeadline();
    error InvalidFreelancer();
    error JobDoesNotExist();
    error Unauthorized();
    error InvalidJobStatus();
    error EmptyDeliveryURI();
    error DeadlinePassed();
    error InvalidFee();
    error DeadlineNotPassed();
    error EmptyDisputeReasonURI();
    error InvalidResolutionAmounts();
    error InvalidReviewPeriod();
    error ReviewPeriodNotPassed();
    error MarketPlaceIsPaused();
    error MarketPlaceNotPaused();
    error InsufficientRecoverableBalance();
    error InvalidETHAmount();
    error ETHTransferFailed();


    event JobCreated(uint256 indexed jobId, address indexed client, address indexed freelancer, address token, uint256 amount, uint256 deadline, string metadataURI);
    event JobFunded(uint256 indexed jobId, address indexed client, address token, uint256 amount);
    event JobAccepted(uint256 indexed jobId, address indexed freelancer);
    event WorkSubmitted(uint256 indexed jobId, address indexed freelancer, string deliveryURI);
    event WorkApproved(uint256 indexed jobId, address indexed client);
    event PaymentReleased(uint256 indexed jobId, address indexed freelancer, uint256 freelancerAmount, uint256 platformFee);
    event JobCancelled(uint256 indexed jobId, address indexed client);
    event ClientRefunded(uint256 indexed jobId, address indexed client, uint256 amount);
    event DisputeOpened(uint256 indexed jobId, address indexed openedBy, string ReasonURI);
    event DisputeResolved(uint256 indexed jobId, address indexed arbitrator, uint256 clientAmount, uint256 freelancerAmount);
    event PaymentClaimedAfterReview(uint256 indexed jobId, address indexed freelancer);
    event MarketPlacePaused(address indexed owner);
    event MarketPlaceUnpaused(address indexed owner);
    event FeeRecipientUpdated(address indexed oldFeeRecipient, address indexed newFeeRecipient);
    event PlatformFeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);
    event ArbitratorUpdated(address indexed oldArbitrator, address indexed newArbitrator);
    event ReviewPeriodUpdated(uint256 oldReviewPeriod, uint256 newReviewPeriod);
    event ERC20Recovered(address indexed token, uint256 amount, address indexed recipient);
    event ETHRecovered(address indexed recipient, uint256 amount);

    modifier onlyOwner() {
        if(msg.sender != owner) {
            revert Unauthorized();
        }
        _;
    }

    modifier whenNotPaused() {
        if(paused) {
            revert MarketPlaceIsPaused();
        }
        _;
    }



    constructor(address feeRecipient_, uint256 platformFeeBps_, address arbitrator_, uint256 reviewPeriod_) {
        if (feeRecipient_ == address(0)) {
            revert InvalidAddress();
        }
        if (arbitrator_ == address(0)) {
            revert InvalidAddress();
        }
        if (platformFeeBps_ > BPS_DENOMINATOR) {
            revert InvalidFee();
        }
        if(reviewPeriod_ == 0) {
            revert InvalidReviewPeriod();
        }
        
        feeRecipient = feeRecipient_;
        platformFeeBps = platformFeeBps_;
        arbitrator = arbitrator_;
        reviewPeriod = reviewPeriod_;

        nextJobId = 1;

        owner = msg.sender;

        paused = false;
    }

    // Internal-Private Functions
    function _transferAsset(address token, address recipient, uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        if (token == address(0)) {
            (bool success, ) = payable(recipient).call{value: amount}("");

            if (!success) {
                revert ETHTransferFailed();
            }
        } else {
            IERC20(token).safeTransfer(recipient, amount);
        }
    }

    // Public-External Functions

    function createJob(address freelancer, address token, uint256 amount, uint256 deadline, string calldata metadataURI) external payable whenNotPaused nonReentrant returns (uint256 jobId)  {
        if (freelancer == address(0)) {
            revert InvalidAddress();
        }

        if (freelancer == msg.sender) {
            revert InvalidFreelancer();
        }

        if (amount == 0) {
            revert InvalidAmount();
        }
        if (deadline <= block.timestamp) {
            revert InvalidDeadline();
        }

        if (token == address(0)) {
            if(msg.value != amount){
                revert InvalidETHAmount();
            }
        } else {
            if (msg.value != 0) {
                revert InvalidETHAmount();
            }
        }

        jobId = nextJobId;

        jobs[jobId] = Job({
            client: msg.sender,
            freelancer: freelancer,
            token: token,
            amount: amount,
            deadline: deadline,
            submittedAt: 0,
            status: JobStatus.Funded,
            metadataURI: metadataURI,
            deliveryURI: "",
            disputeReasonURI: ""
        });

        nextJobId++;

        // Transfer ERC20 funds when applicable.
        if (token != address(0)) {
            IERC20(token).safeTransferFrom(
                msg.sender,
                address(this),
                amount
            );
        }

        // Account for either ERC20 or native ETH.
        totalEscrowed[token] += amount;

        emit JobCreated(jobId, msg.sender, freelancer, token, amount, deadline, metadataURI);
        emit JobFunded(jobId, msg.sender, token, amount);
    }

    function getJob(uint256 jobId) external view returns (Job memory) {
        if (jobId == 0 || jobId >= nextJobId) {
            revert JobDoesNotExist();
        }

        return jobs[jobId];
    }

    function acceptJob (uint256 jobId) external whenNotPaused{
        if(jobId == 0 || jobId >= nextJobId) {
            revert JobDoesNotExist();
        }

        Job storage job = jobs[jobId];
        
        if(msg.sender != job.freelancer) {
            revert Unauthorized();
        }

        if(job.status != JobStatus.Funded) {
            revert InvalidJobStatus();
        }

        job.status = JobStatus.InProgress;
        
        emit JobAccepted(jobId, msg.sender);
    }

    function submitWork(uint256 jobId, string calldata deliveryURI) external whenNotPaused {
        if(jobId == 0 || jobId >= nextJobId) {
            revert JobDoesNotExist();
        }

        Job storage job = jobs[jobId];

        if(msg.sender != job.freelancer) {
            revert Unauthorized();
        }

        if(job.status != JobStatus.InProgress) {
            revert InvalidJobStatus();
        }

        if(block.timestamp > job.deadline) {
            revert DeadlinePassed();
        }

        if(bytes(deliveryURI).length == 0) {
            revert EmptyDeliveryURI();
        }

        job.deliveryURI = deliveryURI;
        job.submittedAt = block.timestamp;
        job.status = JobStatus.Submitted;

        emit WorkSubmitted(jobId, msg.sender, deliveryURI);
    }

    function approveWork(uint256 jobId) external whenNotPaused nonReentrant {
        if(jobId == 0 || jobId >= nextJobId) {
            revert JobDoesNotExist();
        }

        Job storage job = jobs[jobId];

        if(msg.sender != job.client) {
            revert Unauthorized();
        }

        if(job.status != JobStatus.Submitted) {
            revert InvalidJobStatus();
        }

        uint256 fee = (job.amount * platformFeeBps) / BPS_DENOMINATOR;

        uint256 freelancerAmount = job.amount - fee;

        //Effects
        job.status = JobStatus.Completed;
        totalEscrowed[job.token] -= job.amount;

        // Interactions
        _transferAsset(job.token, job.freelancer, freelancerAmount);
        _transferAsset(job.token, feeRecipient, fee);

        emit WorkApproved(jobId, msg.sender);
        emit PaymentReleased(jobId, job.freelancer, freelancerAmount, fee);
    }

    function cancelJob (uint256 jobId) external whenNotPaused nonReentrant {
        if(jobId == 0 || jobId >= nextJobId) {
            revert JobDoesNotExist();
        }

        Job storage job = jobs[jobId];

        if(msg.sender != job.client) {
            revert Unauthorized();
        }

        if(job.status != JobStatus.Funded) {
            revert InvalidJobStatus();
        }

        // Effects
        job.status = JobStatus.Cancelled;
        totalEscrowed[job.token] -= job.amount;

        // Interaction
        _transferAsset(job.token, job.client, job.amount);

        emit JobCancelled(jobId, msg.sender);
        emit ClientRefunded(jobId, msg.sender, job.amount);
    }

    function cancelExpiredJob (uint256 jobId) external whenNotPaused nonReentrant {
        if(jobId == 0 || jobId >= nextJobId) {
            revert JobDoesNotExist();
        }

        Job storage job = jobs[jobId];

        if(msg.sender != job.client) {
            revert Unauthorized();
        }

        if(job.status != JobStatus.InProgress) {
            revert InvalidJobStatus();
        }

        if(block.timestamp <= job.deadline) {
            revert DeadlineNotPassed();
        }

        // Effects
        job.status = JobStatus.Cancelled;
        totalEscrowed[job.token] -= job.amount;

        // Interaction
        _transferAsset(job.token, job.client, job.amount);

        emit JobCancelled(jobId, msg.sender);
        emit ClientRefunded(jobId, msg.sender, job.amount);
    }

    function openDispute(uint256 jobId, string calldata reasonURI) external whenNotPaused {
        if(jobId == 0 || jobId >= nextJobId){
            revert JobDoesNotExist();
        }

        Job storage job = jobs[jobId];

        if(msg.sender != job.client && msg.sender != job.freelancer){
            revert Unauthorized();
        }

        if(job.status != JobStatus.InProgress && job.status != JobStatus.Submitted){
            revert InvalidJobStatus();
        }

        if(bytes(reasonURI).length == 0){
            revert EmptyDisputeReasonURI();
        }

        job.disputeReasonURI = reasonURI;

        job.status = JobStatus.Disputed;

        emit DisputeOpened(jobId, msg.sender, reasonURI);
    }

    function resolveDispute(uint256 jobId, uint256 clientAmount, uint256 freelancerAmount) external whenNotPaused nonReentrant {
        if (jobId == 0 || jobId >= nextJobId) {
            revert JobDoesNotExist();
        }

        if (msg.sender != arbitrator) {
            revert Unauthorized();
        }

        Job storage job = jobs[jobId];

        if (job.status != JobStatus.Disputed) {
            revert InvalidJobStatus();
        }

        if (
            clientAmount > job.amount ||
            freelancerAmount != job.amount - clientAmount
        ) {
            revert InvalidResolutionAmounts();
        }

        uint256 fee =
            (freelancerAmount * platformFeeBps)
            / BPS_DENOMINATOR;

        uint256 freelancerNetAmount = freelancerAmount - fee;

        // Effects
        job.status = JobStatus.Completed;
        totalEscrowed[job.token] -= job.amount;

        // Interactions
        _transferAsset(job.token, job.client, clientAmount);
        _transferAsset(job.token, job.freelancer, freelancerNetAmount);
        _transferAsset(job.token, feeRecipient, fee);

        emit DisputeResolved(
            jobId,
            msg.sender,
            clientAmount,
            freelancerAmount
        );

        if (clientAmount > 0) {
            emit ClientRefunded(jobId, job.client, clientAmount);
        }

        emit PaymentReleased(jobId, job.freelancer, freelancerNetAmount, fee);   
    }

    function claimAfterReviewPeriod(uint256 jobId) external nonReentrant whenNotPaused {
        if (jobId == 0 || jobId >= nextJobId) {
            revert JobDoesNotExist();
        }

        Job storage job = jobs[jobId];

        if (msg.sender != job.freelancer) {
            revert Unauthorized();
        }

        if (job.status != JobStatus.Submitted) {
            revert InvalidJobStatus();
        }

        if (
            block.timestamp <
            job.submittedAt + reviewPeriod
        ) {
            revert ReviewPeriodNotPassed();
        }

        uint256 fee =
            (job.amount * platformFeeBps) / BPS_DENOMINATOR;

        uint256 freelancerAmount = job.amount - fee;

        // Effects
        job.status = JobStatus.Completed;
        totalEscrowed[job.token] -= job.amount;

        // Interactions
        _transferAsset(job.token, job.freelancer, freelancerAmount);
        _transferAsset(job.token, feeRecipient, fee);

        emit PaymentClaimedAfterReview(jobId, msg.sender);
        emit PaymentReleased(jobId, job.freelancer, freelancerAmount, fee);
    }

    function setFeeRecipient(address newFeeRecipient_) external onlyOwner{
        if(newFeeRecipient_ == address(0)){
            revert InvalidAddress();
        }
        address oldFeeRecipient = feeRecipient;
        feeRecipient = newFeeRecipient_;
        emit FeeRecipientUpdated(oldFeeRecipient, newFeeRecipient_);
    }

    function setPlatformFee(uint256 newFeeBps_) external onlyOwner{
        if(newFeeBps_ > BPS_DENOMINATOR){
            revert InvalidFee();
        }
        uint256 oldFeeBps = platformFeeBps;
        platformFeeBps = newFeeBps_;
        emit PlatformFeeUpdated(oldFeeBps, newFeeBps_);
    }

    function setArbitrator(address newArbitrator_) external onlyOwner{
        if(newArbitrator_ == address(0)){
            revert InvalidAddress();
        }
        address oldArbitrator = arbitrator;
        arbitrator = newArbitrator_;
        emit ArbitratorUpdated(oldArbitrator, newArbitrator_);
    }

    function setReviewPeriod(uint256 newReviewPeriod_) external onlyOwner{
        if(newReviewPeriod_ == 0){
            revert InvalidReviewPeriod();
        }
        uint256 oldReviewPeriod = reviewPeriod;
        reviewPeriod = newReviewPeriod_;
        emit ReviewPeriodUpdated(oldReviewPeriod, newReviewPeriod_);
    }

    function recoverERC20(address token, uint256 amount, address recipient) external onlyOwner nonReentrant {
        if(token == address(0)){
            revert InvalidAddress();
        }
        if(amount == 0){
            revert InvalidAmount();
        }
        if(recipient == address(0)){
            revert InvalidAddress();
        }
        
        uint256 balance = IERC20(token).balanceOf(address(this));

        if (balance < totalEscrowed[token]) {
            revert InsufficientRecoverableBalance();
        }

        uint256 recoverable = balance - totalEscrowed[token];

        if (amount > recoverable) {
            revert InsufficientRecoverableBalance();
        }
        
        IERC20(token).safeTransfer(recipient, amount);

        emit ERC20Recovered(token, amount, recipient);
    }

    function recoverETH(uint256 amount, address recipient) external onlyOwner nonReentrant{
        if(amount == 0) {
            revert InvalidAmount();
        }

        if(recipient == address(0)) {
            revert InvalidAddress();
        }

        uint256 balance = address(this).balance;
        uint256 reserved = totalEscrowed[address(0)];

        if(balance < reserved) {
            revert InsufficientRecoverableBalance();
        }

        uint256 recoverable = balance - reserved;

        if(amount > recoverable) {
            revert InsufficientRecoverableBalance();
        }

        _transferAsset(address(0), recipient, amount);

        emit ETHRecovered(recipient, amount);
    }

    function pause() external onlyOwner {
        if(paused) revert MarketPlaceIsPaused();
        paused = true;
        emit MarketPlacePaused(msg.sender);
    }

    function unpause() external onlyOwner {
        if(!paused) revert MarketPlaceNotPaused();
        paused = false;
        emit MarketPlaceUnpaused(msg.sender);
    }
    
}
