// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol"; 

contract EscrowMarketplace {
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

    function createJob(address freelancer, address token, uint256 amount, uint256 deadline, string calldata metadataURI) external whenNotPaused returns (uint256 jobId)  {
        if (freelancer == address(0)) {
            revert InvalidAddress();
        }

        if (token == address(0)) {
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

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

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

    function approveWork(uint256 jobId) external whenNotPaused {
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

        IERC20(job.token).safeTransfer(job.freelancer, freelancerAmount);

        if (fee > 0) {
            IERC20(job.token).safeTransfer(feeRecipient, fee);
        }

        totalEscrowed[job.token] -= job.amount;

        job.status = JobStatus.Completed;

        emit WorkApproved(jobId, msg.sender);
        emit PaymentReleased(jobId, job.freelancer, freelancerAmount, fee);
    }

    function cancelJob (uint256 jobId) external whenNotPaused {
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

        IERC20(job.token).safeTransfer(job.client, job.amount);

        totalEscrowed[job.token] -= job.amount;

        job.status = JobStatus.Cancelled;

        emit JobCancelled(jobId, msg.sender);
        emit ClientRefunded(jobId, msg.sender, job.amount);
    }

    function cancelExpiredJob (uint256 jobId) external whenNotPaused {
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

        IERC20(job.token).safeTransfer(job.client, job.amount);

        totalEscrowed[job.token] -= job.amount;

        job.status = JobStatus.Cancelled;

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

    function resolveDispute(uint256 jobId, uint256 clientAmount, uint256 freelancerAmount) external whenNotPaused {
        if(jobId == 0 || jobId >= nextJobId){
            revert JobDoesNotExist();
        }

        if(msg.sender != arbitrator){
            revert Unauthorized();
        }

        Job storage job = jobs[jobId];

        if(job.status != JobStatus.Disputed){
            revert InvalidJobStatus();
        }

        if(clientAmount + freelancerAmount != job.amount){
            revert InvalidResolutionAmounts();
        }

        uint256 fee = freelancerAmount * platformFeeBps / BPS_DENOMINATOR;
        uint256 freelancerNetAmount = freelancerAmount - fee;

        job.status = JobStatus.Completed;

        if(clientAmount > 0) {
            IERC20(job.token).safeTransfer(job.client, clientAmount);
        }

        if(freelancerNetAmount > 0) {
            IERC20(job.token).safeTransfer(job.freelancer, freelancerNetAmount);
        }

        if(fee > 0) {
            IERC20(job.token).safeTransfer(feeRecipient, fee);
        }

        emit DisputeResolved(jobId, msg.sender, clientAmount, freelancerAmount);

        if(clientAmount > 0) {
            emit ClientRefunded(jobId, job.client, clientAmount);
        }
        
        totalEscrowed[job.token] -= job.amount;

        emit PaymentReleased(jobId, job.freelancer, freelancerNetAmount, fee);   
    }

    function claimAfterReviewPeriod(uint256 jobId) external whenNotPaused {
        if(jobId == 0 || jobId >= nextJobId){
            revert JobDoesNotExist();
        }

        Job storage job = jobs[jobId];

        if(msg.sender != job.freelancer){
            revert Unauthorized();
        }

        if(job.status != JobStatus.Submitted){
            revert InvalidJobStatus();
        }

        if(block.timestamp < job.submittedAt + reviewPeriod){
            revert ReviewPeriodNotPassed();
        }

        uint256 fee = job.amount * platformFeeBps / BPS_DENOMINATOR;
        uint256 freelancerNetAmount = job.amount - fee;

        IERC20(job.token).safeTransfer(job.freelancer, freelancerNetAmount);
        if(fee > 0){
            IERC20(job.token).safeTransfer(feeRecipient, fee);
        }

        totalEscrowed[job.token] -= job.amount;

        job.status = JobStatus.Completed;

        emit PaymentClaimedAfterReview(jobId, msg.sender);
        emit PaymentReleased(jobId, job.freelancer, freelancerNetAmount, fee);
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

    function recoverERC20(address token, uint256 amount, address recipient) external onlyOwner {
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
