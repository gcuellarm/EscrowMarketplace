// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract EscrowMarketplace {
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
    }

    uint256 public nextJobId;

    mapping(uint256 => Job) private jobs;

    error InvalidAddress();
    error InvalidAmount();
    error InvalidDeadline();
    error InvalidFreelancer();
    error JobDoesNotExist();

    event JobCreated(uint256 indexed jobId, address indexed client, address indexed freelancer, address token, uint256 amount, uint256 deadline, string metadataURI);

    constructor() {
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
            status: JobStatus.Created,
            metadataURI: metadataURI
        });

        nextJobId++;

        emit JobCreated(jobId, msg.sender, freelancer, token, amount, deadline, metadataURI);
    }

    function getJob(uint256 jobId) external view returns (Job memory) {
        if (jobId == 0 || jobId >= nextJobId) {
            revert JobDoesNotExist();
        }

        return jobs[jobId];
    }
}