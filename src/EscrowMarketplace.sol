// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol"; 
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title EscrowMarketplace
/// @notice Escrows native ETH or ERC20 payments for freelance jobs and manages their lifecycle.
/// @dev The zero address represents native ETH. Administrative authority is assigned to the deployer.
contract EscrowMarketplace is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Possible states in a job's lifecycle.
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

    /// @notice Complete state associated with an escrowed job.
    /// @param client Address that created and funded the job.
    /// @param freelancer Address assigned to perform the job.
    /// @param token Payment token, or the zero address for native ETH.
    /// @param amount Gross amount held in escrow.
    /// @param deadline Latest timestamp at which work may be submitted.
    /// @param submittedAt Timestamp at which work was submitted, or zero before submission.
    /// @param status Current lifecycle status.
    /// @param metadataURI URI containing the job requirements or metadata.
    /// @param deliveryURI URI containing the submitted work.
    /// @param disputeReasonURI URI containing the dispute details.
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

    /// @notice Identifier that will be assigned to the next job.
    uint256 public nextJobId;

    /// @notice Denominator used for basis-point fee calculations.
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Platform fee charged on amounts paid to freelancers, in basis points.
    uint256 public platformFeeBps;
    /// @notice Address that receives platform fees.
    address public feeRecipient;
    /// @notice Address authorized to resolve disputes.
    address public arbitrator;
    /// @notice Time freelancers must wait after submission before claiming payment.
    uint256 public reviewPeriod;
    /// @notice Address authorized to manage and pause the marketplace.
    address public owner;
    /// @notice Whether lifecycle-changing marketplace operations are paused.
    bool public paused;

    mapping(uint256 => Job) private jobs;

    /// @notice Total reserved escrow balance for each asset, using the zero address for ETH.
    mapping(address => uint256) public totalEscrowed;

    /// @notice Job identifiers created by each client.
    mapping(address => uint256[]) public clientJobs;
    /// @notice Job identifiers assigned to each freelancer.
    mapping(address => uint256[]) public freelancerJobs;


    /// @notice A required address is the zero address.
    error InvalidAddress();
    /// @notice An amount is zero.
    error InvalidAmount();
    /// @notice The supplied deadline is not in the future.
    error InvalidDeadline();
    /// @notice The client is also the assigned freelancer.
    error InvalidFreelancer();
    /// @notice The requested job identifier does not exist.
    error JobDoesNotExist();
    /// @notice The caller is not authorized to perform the operation.
    error Unauthorized();
    /// @notice The job is not in a status accepted by the operation.
    error InvalidJobStatus();
    /// @notice The submitted delivery URI is empty.
    error EmptyDeliveryURI();
    /// @notice The job deadline has passed.
    error DeadlinePassed();
    /// @notice The platform fee exceeds the basis-point denominator.
    error InvalidFee();
    /// @notice The job deadline has not passed yet.
    error DeadlineNotPassed();
    /// @notice The supplied dispute reason URI is empty.
    error EmptyDisputeReasonURI();
    /// @notice The dispute allocation does not equal the gross escrowed amount.
    error InvalidResolutionAmounts();
    /// @notice The review period is zero.
    error InvalidReviewPeriod();
    /// @notice The review period following submission has not elapsed.
    error ReviewPeriodNotPassed();
    /// @notice The marketplace is paused.
    error MarketPlaceIsPaused();
    /// @notice The marketplace is not paused.
    error MarketPlaceNotPaused();
    /// @notice The requested recovery would consume escrowed funds or exceed the balance.
    error InsufficientRecoverableBalance();
    /// @notice The ETH supplied does not match the selected payment asset and amount.
    error InvalidETHAmount();
    /// @notice A native ETH transfer failed.
    error ETHTransferFailed();


    /// @notice Emitted when a client creates and funds a job.
    /// @param jobId Job identifier.
    /// @param client Client that created the job.
    /// @param freelancer Freelancer assigned to the job.
    /// @param token Payment token, or the zero address for ETH.
    /// @param amount Gross amount placed in escrow.
    /// @param deadline Work submission deadline.
    /// @param metadataURI URI containing job metadata.
    event JobCreated(uint256 indexed jobId, address indexed client, address indexed freelancer, address token, uint256 amount, uint256 deadline, string metadataURI);
    /// @notice Emitted when a job is funded.
    /// @param jobId Job identifier.
    /// @param client Client that supplied the funds.
    /// @param token Payment token, or the zero address for ETH.
    /// @param amount Amount placed in escrow.
    event JobFunded(uint256 indexed jobId, address indexed client, address token, uint256 amount);
    /// @notice Emitted when the assigned freelancer accepts a job.
    /// @param jobId Job identifier.
    /// @param freelancer Freelancer that accepted the job.
    event JobAccepted(uint256 indexed jobId, address indexed freelancer);
    /// @notice Emitted when the freelancer submits work.
    /// @param jobId Job identifier.
    /// @param freelancer Freelancer that submitted the work.
    /// @param deliveryURI URI containing the delivery.
    event WorkSubmitted(uint256 indexed jobId, address indexed freelancer, string deliveryURI);
    /// @notice Emitted when the client approves submitted work.
    /// @param jobId Job identifier.
    /// @param client Client that approved the work.
    event WorkApproved(uint256 indexed jobId, address indexed client);
    /// @notice Emitted when a freelancer payment and platform fee are released.
    /// @param jobId Job identifier.
    /// @param freelancer Freelancer receiving the net payment.
    /// @param freelancerAmount Net amount paid to the freelancer.
    /// @param platformFee Fee paid to the fee recipient.
    event PaymentReleased(uint256 indexed jobId, address indexed freelancer, uint256 freelancerAmount, uint256 platformFee);
    /// @notice Emitted when a client cancels a job.
    /// @param jobId Job identifier.
    /// @param client Client that cancelled the job.
    event JobCancelled(uint256 indexed jobId, address indexed client);
    /// @notice Emitted when escrowed funds are returned to a client.
    /// @param jobId Job identifier.
    /// @param client Client receiving the refund.
    /// @param amount Amount refunded.
    event ClientRefunded(uint256 indexed jobId, address indexed client, uint256 amount);
    /// @notice Emitted when a client or freelancer opens a dispute.
    /// @param jobId Job identifier.
    /// @param openedBy Address that opened the dispute.
    /// @param ReasonURI URI containing the dispute reason.
    event DisputeOpened(uint256 indexed jobId, address indexed openedBy, string ReasonURI);
    /// @notice Emitted when the arbitrator resolves a dispute.
    /// @param jobId Job identifier.
    /// @param arbitrator Arbitrator that resolved the dispute.
    /// @param clientAmount Gross amount allocated to the client.
    /// @param freelancerAmount Gross amount allocated to the freelancer before fees.
    event DisputeResolved(uint256 indexed jobId, address indexed arbitrator, uint256 clientAmount, uint256 freelancerAmount);
    /// @notice Emitted when a freelancer claims payment after the review period.
    /// @param jobId Job identifier.
    /// @param freelancer Freelancer that claimed payment.
    event PaymentClaimedAfterReview(uint256 indexed jobId, address indexed freelancer);
    /// @notice Emitted when the owner pauses the marketplace.
    /// @param owner Owner that paused the marketplace.
    event MarketPlacePaused(address indexed owner);
    /// @notice Emitted when the owner unpauses the marketplace.
    /// @param owner Owner that unpaused the marketplace.
    event MarketPlaceUnpaused(address indexed owner);
    /// @notice Emitted when the fee recipient is updated.
    /// @param oldFeeRecipient Previous fee recipient.
    /// @param newFeeRecipient New fee recipient.
    event FeeRecipientUpdated(address indexed oldFeeRecipient, address indexed newFeeRecipient);
    /// @notice Emitted when the platform fee is updated.
    /// @param oldFeeBps Previous fee in basis points.
    /// @param newFeeBps New fee in basis points.
    event PlatformFeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);
    /// @notice Emitted when the arbitrator is updated.
    /// @param oldArbitrator Previous arbitrator.
    /// @param newArbitrator New arbitrator.
    event ArbitratorUpdated(address indexed oldArbitrator, address indexed newArbitrator);
    /// @notice Emitted when the review period is updated.
    /// @param oldReviewPeriod Previous review period.
    /// @param newReviewPeriod New review period.
    event ReviewPeriodUpdated(uint256 oldReviewPeriod, uint256 newReviewPeriod);
    /// @notice Emitted when surplus ERC20 tokens are recovered.
    /// @param token Recovered token.
    /// @param amount Amount recovered.
    /// @param recipient Address receiving the tokens.
    event ERC20Recovered(address indexed token, uint256 amount, address indexed recipient);
    /// @notice Emitted when surplus ETH is recovered.
    /// @param recipient Address receiving the ETH.
    /// @param amount Amount recovered.
    event ETHRecovered(address indexed recipient, uint256 amount);

    /// @notice Restricts an operation to the marketplace owner.
    modifier onlyOwner() {
        if(msg.sender != owner) {
            revert Unauthorized();
        }
        _;
    }

    /// @notice Restricts an operation to periods when the marketplace is not paused.
    modifier whenNotPaused() {
        if(paused) {
            revert MarketPlaceIsPaused();
        }
        _;
    }



    /// @notice Deploys the marketplace with its initial fee, arbitrator, and review configuration.
    /// @param feeRecipient_ Address that will receive platform fees.
    /// @param platformFeeBps_ Platform fee in basis points, up to 10,000.
    /// @param arbitrator_ Address authorized to resolve disputes.
    /// @param reviewPeriod_ Time freelancers must wait after submission before claiming payment.
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
    /// @notice Transfers ETH or ERC20 tokens to a recipient.
    /// @param token Asset to transfer, or the zero address for ETH.
    /// @param recipient Address receiving the asset.
    /// @param amount Amount to transfer; zero amounts are ignored.
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

    /// @notice Returns a storage reference for an existing job.
    /// @param jobId Identifier of the job.
    /// @return job Storage reference to the job.
    function _getJobStorage(
        uint256 jobId
    ) internal view returns (Job storage job) {
        if (jobId == 0 || jobId >= nextJobId) {
            revert JobDoesNotExist();
        }

        job = jobs[jobId];
    }

    /// @notice Calculates the current platform fee for an amount.
    /// @param amount Gross freelancer allocation.
    /// @return Platform fee rounded down to the nearest wei or token unit.
    function _calculateFee(uint256 amount) internal view returns (uint256) {
        return (amount * platformFeeBps) / BPS_DENOMINATOR;
    }

    // Public-External Functions

    /// @notice Creates a job and funds its escrow in the same transaction.
    /// @dev Send exactly `amount` as `msg.value` for ETH jobs; approve the contract first for ERC20 jobs.
    /// @param freelancer Address assigned to perform the work.
    /// @param token Payment token, or the zero address for native ETH.
    /// @param amount Gross amount to escrow.
    /// @param deadline Future work submission deadline.
    /// @param metadataURI URI containing job requirements or metadata.
    /// @return jobId Identifier assigned to the new job.
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

        clientJobs[msg.sender].push(jobId);
        freelancerJobs[freelancer].push(jobId);

        unchecked {
            ++nextJobId;
        }

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

    /// @notice Returns all stored data for an existing job.
    /// @param jobId Identifier of the job.
    /// @return The job data.
    function getJob(uint256 jobId) external view returns (Job memory) {
        return _getJobStorage(jobId);
    }

    /// @notice Lets the assigned freelancer accept a funded job.
    /// @param jobId Identifier of the job.
    function acceptJob (uint256 jobId) external whenNotPaused{
        Job storage job = _getJobStorage(jobId);
        
        if(msg.sender != job.freelancer) {
            revert Unauthorized();
        }

        if(job.status != JobStatus.Funded) {
            revert InvalidJobStatus();
        }

        job.status = JobStatus.InProgress;
        
        emit JobAccepted(jobId, msg.sender);
    }

    /// @notice Submits work for an accepted job on or before its deadline.
    /// @param jobId Identifier of the job.
    /// @param deliveryURI Non-empty URI containing the delivery.
    function submitWork(uint256 jobId, string calldata deliveryURI) external whenNotPaused {
        Job storage job = _getJobStorage(jobId);

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

    /// @notice Lets the client approve submitted work and releases payment less the platform fee.
    /// @param jobId Identifier of the job.
    function approveWork(uint256 jobId) external whenNotPaused nonReentrant {
        Job storage job = _getJobStorage(jobId);

        if(msg.sender != job.client) {
            revert Unauthorized();
        }

        if(job.status != JobStatus.Submitted) {
            revert InvalidJobStatus();
        }

        uint256 jobAmount = job.amount;
        address jobToken = job.token;
        address jobFreelancer = job.freelancer;
        uint256 fee = _calculateFee(jobAmount);
        uint256 freelancerAmount = jobAmount - fee;

        //Effects
        job.status = JobStatus.Completed;
        totalEscrowed[jobToken] -= jobAmount;

        // Interactions
        _transferAsset(jobToken, jobFreelancer, freelancerAmount);
        _transferAsset(jobToken, feeRecipient, fee);

        emit WorkApproved(jobId, msg.sender);
        emit PaymentReleased(jobId, jobFreelancer, freelancerAmount, fee);
    }

    /// @notice Lets the client cancel a funded job before it is accepted and receive a full refund.
    /// @param jobId Identifier of the job.
    function cancelJob (uint256 jobId) external whenNotPaused nonReentrant {
        Job storage job = _getJobStorage(jobId);
        address jobClient = job.client;

        if(msg.sender != jobClient) {
            revert Unauthorized();
        }

        if(job.status != JobStatus.Funded) {
            revert InvalidJobStatus();
        }

        uint256 jobAmount = job.amount;
        address jobToken = job.token;

        // Effects
        job.status = JobStatus.Cancelled;
        totalEscrowed[jobToken] -= jobAmount;

        // Interaction
        _transferAsset(jobToken, jobClient, jobAmount);

        emit JobCancelled(jobId, msg.sender);
        emit ClientRefunded(jobId, msg.sender, jobAmount);
    }

    /// @notice Lets the client cancel an in-progress job after its deadline and receive a full refund.
    /// @param jobId Identifier of the job.
    function cancelExpiredJob (uint256 jobId) external whenNotPaused nonReentrant {
        Job storage job = _getJobStorage(jobId);
        address jobClient = job.client;

        if(msg.sender != jobClient) {
            revert Unauthorized();
        }

        if(job.status != JobStatus.InProgress) {
            revert InvalidJobStatus();
        }

        if(block.timestamp <= job.deadline) {
            revert DeadlineNotPassed();
        }

        uint256 jobAmount = job.amount;
        address jobToken = job.token;

        // Effects
        job.status = JobStatus.Cancelled;
        totalEscrowed[jobToken] -= jobAmount;

        // Interaction
        _transferAsset(jobToken, jobClient, jobAmount);

        emit JobCancelled(jobId, msg.sender);
        emit ClientRefunded(jobId, msg.sender, jobAmount);
    }

    /// @notice Opens a dispute for an in-progress or submitted job.
    /// @param jobId Identifier of the job.
    /// @param reasonURI Non-empty URI containing the dispute reason.
    function openDispute(uint256 jobId, string calldata reasonURI) external whenNotPaused {
        Job storage job = _getJobStorage(jobId);

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

    /// @notice Resolves a dispute by allocating the complete gross escrow between both parties.
    /// @dev Only the arbitrator may call this function. The platform fee applies to the freelancer allocation.
    /// @param jobId Identifier of the disputed job.
    /// @param clientAmount Gross amount returned to the client.
    /// @param freelancerAmount Gross freelancer allocation before the platform fee.
    function resolveDispute(uint256 jobId, uint256 clientAmount, uint256 freelancerAmount) external whenNotPaused nonReentrant {
        Job storage job = _getJobStorage(jobId);

        if (msg.sender != arbitrator) {
            revert Unauthorized();
        }

        if (job.status != JobStatus.Disputed) {
            revert InvalidJobStatus();
        }

        uint256 jobAmount = job.amount;

        if (
            clientAmount > jobAmount ||
            freelancerAmount != jobAmount - clientAmount
        ) {
            revert InvalidResolutionAmounts();
        }

        address jobToken = job.token;
        address jobClient = job.client;
        address jobFreelancer = job.freelancer;
        uint256 fee = _calculateFee(freelancerAmount);
        uint256 freelancerNetAmount = freelancerAmount - fee;

        // Effects
        job.status = JobStatus.Completed;
        totalEscrowed[jobToken] -= jobAmount;

        // Interactions
        _transferAsset(jobToken, jobClient, clientAmount);
        _transferAsset(jobToken, jobFreelancer, freelancerNetAmount);
        _transferAsset(jobToken, feeRecipient, fee);

        emit DisputeResolved(
            jobId,
            msg.sender,
            clientAmount,
            freelancerAmount
        );

        if (clientAmount > 0) {
            emit ClientRefunded(jobId, jobClient, clientAmount);
        }

        emit PaymentReleased(jobId, jobFreelancer, freelancerNetAmount, fee);
    }

    /// @notice Lets the freelancer claim payment when submitted work remains unresolved through the review period.
    /// @param jobId Identifier of the submitted job.
    function claimAfterReviewPeriod(uint256 jobId) external nonReentrant whenNotPaused {
        Job storage job = _getJobStorage(jobId);
        address jobFreelancer = job.freelancer;

        if (msg.sender != jobFreelancer) {
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

        uint256 jobAmount = job.amount;
        address jobToken = job.token;
        uint256 fee = _calculateFee(jobAmount);
        uint256 freelancerAmount = jobAmount - fee;

        // Effects
        job.status = JobStatus.Completed;
        totalEscrowed[jobToken] -= jobAmount;

        // Interactions
        _transferAsset(jobToken, jobFreelancer, freelancerAmount);
        _transferAsset(jobToken, feeRecipient, fee);

        emit PaymentClaimedAfterReview(jobId, msg.sender);
        emit PaymentReleased(jobId, jobFreelancer, freelancerAmount, fee);
    }

    /// @notice Updates the address that receives future platform fees.
    /// @param newFeeRecipient_ New non-zero fee recipient.
    function setFeeRecipient(address newFeeRecipient_) external onlyOwner{
        if(newFeeRecipient_ == address(0)){
            revert InvalidAddress();
        }
        address oldFeeRecipient = feeRecipient;
        feeRecipient = newFeeRecipient_;
        emit FeeRecipientUpdated(oldFeeRecipient, newFeeRecipient_);
    }

    /// @notice Updates the platform fee charged on future freelancer payments.
    /// @param newFeeBps_ New fee in basis points, up to 10,000.
    function setPlatformFee(uint256 newFeeBps_) external onlyOwner{
        if(newFeeBps_ > BPS_DENOMINATOR){
            revert InvalidFee();
        }
        uint256 oldFeeBps = platformFeeBps;
        platformFeeBps = newFeeBps_;
        emit PlatformFeeUpdated(oldFeeBps, newFeeBps_);
    }

    /// @notice Updates the address authorized to resolve disputes.
    /// @param newArbitrator_ New non-zero arbitrator address.
    function setArbitrator(address newArbitrator_) external onlyOwner{
        if(newArbitrator_ == address(0)){
            revert InvalidAddress();
        }
        address oldArbitrator = arbitrator;
        arbitrator = newArbitrator_;
        emit ArbitratorUpdated(oldArbitrator, newArbitrator_);
    }

    /// @notice Updates the waiting period for freelancer claims after submission.
    /// @param newReviewPeriod_ New non-zero review period in seconds.
    function setReviewPeriod(uint256 newReviewPeriod_) external onlyOwner{
        if(newReviewPeriod_ == 0){
            revert InvalidReviewPeriod();
        }
        uint256 oldReviewPeriod = reviewPeriod;
        reviewPeriod = newReviewPeriod_;
        emit ReviewPeriodUpdated(oldReviewPeriod, newReviewPeriod_);
    }

    /// @notice Recovers ERC20 tokens held by the contract that are not reserved for active escrows.
    /// @dev The recoverable balance is the contract balance minus `totalEscrowed[token]`.
    /// @param token Non-zero address of the ERC20 token to recover.
    /// @param amount Amount of surplus tokens to recover.
    /// @param recipient Non-zero address receiving the recovered tokens.
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

    /// @notice Recovers native ETH held by the contract that is not reserved for active escrows.
    /// @dev The recoverable balance is the contract balance minus `totalEscrowed[address(0)]`.
    /// @param amount Amount of surplus ETH to recover.
    /// @param recipient Non-zero address receiving the recovered ETH.
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

    /// @notice Returns every job identifier created by a client.
    /// @param client Client whose job history is requested.
    /// @return Job identifiers in creation order.
    function getClientJobIds(address client) external view returns(uint256[]memory){
        return clientJobs[client];
    }

    /// @notice Returns every job identifier assigned to a freelancer.
    /// @param freelancer Freelancer whose job history is requested.
    /// @return Job identifiers in creation order.
    function getFreelancerJobIds(address freelancer) external view returns(uint256[]memory){
        return freelancerJobs[freelancer];
    }

    /// @notice Returns the number of jobs created by a client.
    /// @param client Client whose job count is requested.
    /// @return Number of jobs in the client's history.
    function getClientJobCount(address client) external view returns(uint256){
        return clientJobs[client].length;
    }

    /// @notice Returns the number of jobs assigned to a freelancer.
    /// @param freelancer Freelancer whose job count is requested.
    /// @return Number of jobs in the freelancer's history.
    function getFreelancerJobCount(address freelancer) external view returns(uint256){
        return freelancerJobs[freelancer].length;
    }

    /// @notice Pauses lifecycle-changing marketplace operations.
    /// @dev Recovery, configuration, history, and read operations remain available while paused.
    function pause() external onlyOwner {
        if(paused) revert MarketPlaceIsPaused();
        paused = true;
        emit MarketPlacePaused(msg.sender);
    }

    /// @notice Resumes lifecycle-changing marketplace operations.
    function unpause() external onlyOwner {
        if(!paused) revert MarketPlaceNotPaused();
        paused = false;
        emit MarketPlaceUnpaused(msg.sender);
    }
    
}
