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
        JobStatus status;
        string metadataURI;
        string deliveryURI;
    }

    uint256 public nextJobId;

    uint256 public constant BPS_DENOMINATOR = 10_000;

    uint256 public platformFeeBps;
    address public feeRecipient;

    mapping(uint256 => Job) private jobs;

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


    event JobCreated(uint256 indexed jobId, address indexed client, address indexed freelancer, address token, uint256 amount, uint256 deadline, string metadataURI);
    event JobFunded(uint256 indexed jobId, address indexed client, address token, uint256 amount);
    event JobAccepted(uint256 indexed jobId, address indexed freelancer);
    event WorkSubmitted(uint256 indexed jobId, address indexed freelancer, string deliveryURI);
    event WorkApproved(uint256 indexed jobId, address indexed client);
    event PaymentReleased(uint256 indexed jobId, address indexed freelancer, uint256 freelancerAmount, uint256 platformFee);
    event JobCancelled(uint256 indexed jobId, address indexed client);
    event ClientRefunded(uint256 indexed jobId, address indexed client, uint256 amount);



    constructor(address feeRecipient_, uint256 platformFeeBps_) {
        if (feeRecipient_ == address(0)) {
            revert InvalidAddress();
        }
        if (platformFeeBps_ > BPS_DENOMINATOR) {
            revert InvalidFee();
        }
        
        feeRecipient = feeRecipient_;
        platformFeeBps = platformFeeBps_;

        nextJobId = 1;
    }

    function createJob(address freelancer, address token, uint256 amount, uint256 deadline, string calldata metadataURI) external returns (uint256 jobId) {
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
            status: JobStatus.Funded,
            metadataURI: metadataURI,
            deliveryURI: ""
        });

        nextJobId++;

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit JobCreated(jobId, msg.sender, freelancer, token, amount, deadline, metadataURI);
        emit JobFunded(jobId, msg.sender, token, amount);
    }

    function getJob(uint256 jobId) external view returns (Job memory) {
        if (jobId == 0 || jobId >= nextJobId) {
            revert JobDoesNotExist();
        }

        return jobs[jobId];
    }

    function acceptJob (uint256 jobId) external{
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

    function submitWork(uint256 jobId, string calldata deliveryURI) external {
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
        job.status = JobStatus.Submitted;

        emit WorkSubmitted(jobId, msg.sender, deliveryURI);
    }

    function approveWork(uint256 jobId) external {
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

        uint256 freelancerPayment = job.amount - fee;

        uint256 freelancerAmount = job.amount - fee;

        job.status = JobStatus.Completed;

        IERC20(job.token).safeTransfer(job.freelancer, freelancerAmount);

        if (fee > 0) {
            IERC20(job.token).safeTransfer(feeRecipient, fee);
        }

        emit WorkApproved(jobId, msg.sender);
        emit PaymentReleased(jobId, job.freelancer, freelancerAmount, fee);
    }

    function cancelJob (uint256 jobId) external {
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

        job.status = JobStatus.Cancelled;

        IERC20(job.token).safeTransfer(job.client, job.amount);

        emit JobCancelled(jobId, msg.sender);
        emit ClientRefunded(jobId, msg.sender, job.amount);
    }

    function cancelExpiredJob (uint256 jobId) external {
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

        job.status = JobStatus.Cancelled;

        IERC20(job.token).safeTransfer(job.client, job.amount);

        emit JobCancelled(jobId, msg.sender);
        emit ClientRefunded(jobId, msg.sender, job.amount);
    }
    
}