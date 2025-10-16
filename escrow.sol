// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title LockedTokenGovernance
 * @notice Voting power comes from tokens locked for time. No imports, no constructor, no input parameters.
 * @dev - Call initialize() once after deployment to set the owner/admin.
 *      - Lock ETH via lock30Days(), lock90Days(), lock365Days() (payable). 1 wei = 1 token unit.
 *      - Voting power = lockedAmount * remainingLockDuration / (30 days) (minimum 1 if lockedAmount>0).
 *      - Votes snapshot weight at vote time (later withdraws/extensions don't change past votes).
 *      - Single active proposal at a time. Off-chain metadata is recommended (see events).
 */
contract LockedTokenGovernance {
    // ---- Admin / Globals ----
    address public owner;

    // ---- Locking / Token model ----
    struct Lock {
        uint256 amount;      // total locked amount (wei)
        uint256 unlockTime;  // epoch seconds when funds unlock
    }
    mapping(address => Lock) public locks;
    uint256 public totalLocked; // sum of amounts locked (for info)

    // Predefined durations
    uint256 public constant D30 = 30 days;
    uint256 public constant D90 = 90 days;
    uint256 public constant D365 = 365 days;

    // ---- Proposal / Voting ----
    uint256 public proposalCount;
    uint256 public constant VOTING_PERIOD = 3 days; // default voting window
    struct Proposal {
        uint256 id;
        address proposer;
        uint256 startTime;
        uint256 endTime;
        uint256 yesWeight;
        uint256 noWeight;
        bool executed;
        bool exists;
        string metadataCID; // optional off-chain pointer (can be set via calldata helper)
    }
    Proposal public activeProposal;

    // Track votes per proposal
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => mapping(address => uint256)) public weightUsedInVote;

    // ---- Events ----
    event Initialized(address indexed owner);
    event Locked(address indexed user, uint256 amount, uint256 unlockTime, uint256 totalLockedForUser);
    event Withdrawn(address indexed user, uint256 amount);
    event ProposalCreated(uint256 indexed id, address indexed proposer, uint256 startTime, uint256 endTime);
    event ProposalMetadataSet(uint256 indexed id, string cid);
    event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 weightUsed);
    event ProposalExecuted(uint256 indexed id, bool passed, uint256 yesWeight, uint256 noWeight);

    // ---- Initialization (no constructor) ----
    function initialize() external {
        require(owner == address(0), "Already initialized");
        owner = msg.sender;
        proposalCount = 0;
        emit Initialized(owner);
    }

    // ---- Locking functions (no input parameters) ----
    // Users lock ETH by calling one of these payable functions.
    function lock30Days() external payable {
        _lockForDuration(D30);
    }
    function lock90Days() external payable {
        _lockForDuration(D90);
    }
    function lock365Days() external payable {
        _lockForDuration(D365);
    }

    // Internal lock handler
    function _lockForDuration(uint256 duration) internal {
        require(msg.value > 0, "Send ETH to lock");
        require(duration >= D30, "Invalid duration");

        Lock storage userLock = locks[msg.sender];

        // If current unlockTime is in the future, extend by setting unlockTime = max(current, now + duration)
        uint256 newUnlock = block.timestamp + duration;
        if (userLock.unlockTime >= block.timestamp) {
            // still locked: extend to the later of existing unlock or newUnlock
            if (newUnlock > userLock.unlockTime) {
                userLock.unlockTime = newUnlock;
            }
            userLock.amount += msg.value;
        } else {
            // no existing lock or expired — create new lock
            userLock.amount = msg.value;
            userLock.unlockTime = newUnlock;
        }

        totalLocked += msg.value;

        emit Locked(msg.sender, msg.value, userLock.unlockTime, userLock.amount);
    }

    // Withdraw unlocked funds (no input params)
    function withdrawUnlocked() external {
        Lock storage userLock = locks[msg.sender];
        require(userLock.amount > 0, "No locked funds");
        require(block.timestamp >= userLock.unlockTime, "Lock not expired");

        uint256 amt = userLock.amount;

        // reset lock
        userLock.amount = 0;
        userLock.unlockTime = 0;

        totalLocked -= amt;

        (bool sent, ) = payable(msg.sender).call{value: amt}("");
        require(sent, "Withdraw failed");

        emit Withdrawn(msg.sender, amt);
    }

    // View helpers for lock/voting weight
    function getLockedAmount(address user) external view returns (uint256) {
        return locks[user].amount;
    }
    function getUnlockTime(address user) external view returns (uint256) {
        return locks[user].unlockTime;
    }

    /**
     * @notice Computes current voting weight for a user based on locked amount and remaining lock time.
     * Weight formula: weight = amount * remainingSeconds / (30 days)
     * Minimum: if amount>0 and computed weight == 0 -> returns 1
     */
    function currentVotingWeight(address user) public view returns (uint256) {
        Lock memory L = locks[user];
        if (L.amount == 0) return 0;
        if (L.unlockTime <= block.timestamp) return 0;
        uint256 remaining = L.unlockTime - block.timestamp;
        uint256 weight = (L.amount * remaining) / D30; // normalized to 30-day units
        if (weight == 0) {
            // ensure minimal influence for small amounts / short remaining times
            return 1;
        }
        return weight;
    }

    // ---- Proposal lifecycle (parameter-free API) ----
    function createProposal() external {
        require(owner != address(0), "Not initialized");
        require(!activeProposal.exists || block.timestamp >= activeProposal.endTime, "Active proposal running");

        uint256 id = ++proposalCount;
        uint256 start = block.timestamp;
        uint256 end = block.timestamp + VOTING_PERIOD;

        activeProposal = Proposal({
            id: id,
            proposer: msg.sender,
            startTime: start,
            endTime: end,
            yesWeight: 0,
            noWeight: 0,
            executed: false,
            exists: true,
            metadataCID: ""
        });

        emit ProposalCreated(id, msg.sender, start, end);
    }

    /**
     * Optional: the proposer can set a metadata CID using calldata bytes.
     * Call this function with calldata containing the ASCII CID after the function selector.
     * Many wallets do not allow raw calldata editing — publishing metadata off-chain and linking by event is recommended.
     */
    function setProposalMetadataWithCalldata() external {
        require(activeProposal.exists, "No active proposal");
        require(msg.sender == activeProposal.proposer, "Only proposer");
        uint256 dataSize = msg.data.length;
        if (dataSize > 4) {
            bytes memory payload = new bytes(dataSize - 4);
            for (uint256 i = 4; i < dataSize; i++) {
                payload[i - 4] = msg.data[i];
            }
            activeProposal.metadataCID = string(payload);
            emit ProposalMetadataSet(activeProposal.id, activeProposal.metadataCID);
        }
    }

    // ---- Voting (no input params) ----
    function voteYes() external {
        _vote(true);
    }
    function voteNo() external {
        _vote(false);
    }

    function _vote(bool support) internal {
        require(activeProposal.exists, "No active proposal");
        require(block.timestamp >= activeProposal.startTime, "Not started");
        require(block.timestamp < activeProposal.endTime, "Voting ended");
        require(!hasVoted[activeProposal.id][msg.sender], "Already voted");

        uint256 weight = currentVotingWeight(msg.sender);
        require(weight > 0, "No voting power (lock tokens)");

        // record vote and snapshot weight
        hasVoted[activeProposal.id][msg.sender] = true;
        weightUsedInVote[activeProposal.id][msg.sender] = weight;

        if (support) {
            activeProposal.yesWeight += weight;
        } else {
            activeProposal.noWeight += weight;
        }

        emit Voted(activeProposal.id, msg.sender, support, weight);
    }

    // Execute after voting period ends. Anyone can call.
    function executeProposal() external {
        require(activeProposal.exists, "No active proposal");
        require(block.timestamp >= activeProposal.endTime, "Voting not ended");
        require(!activeProposal.executed, "Already executed");

        uint256 yes = activeProposal.yesWeight;
        uint256 no = activeProposal.noWeight;

        // simple majority check (yes > no). No quorum enforced here but could be added.
        bool passed = (yes > no);

        activeProposal.executed = true;

        emit ProposalExecuted(activeProposal.id, passed, yes, no);

        // Clear active proposal
        delete activeProposal;
    }

    // ---- Utilities / emergency ----
    // Owner-only emergency drain (not governance funds, demo only)
    function emergencyWithdrawAll() external {
        require(owner != address(0), "Not initialized");
        require(msg.sender == owner, "Only owner");
        uint256 bal = address(this).balance;
        require(bal > 0, "No balance");
        (bool sent, ) = payable(owner).call{value: bal}("");
        require(sent, "Withdraw failed");
    }

    // Fallback to accept ETH (but locking must be done via lock functions to set durations)
    receive() external payable {}
}

