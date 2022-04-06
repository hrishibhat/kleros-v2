// SPDX-License-Identifier: MIT

/**
 *  @authors: [@jaybuidl, @shalzz, @hrishibhat, @shotaronowhere]
 *  @reviewers: []
 *  @auditors: []
 *  @bounties: []
 *  @deployments: []
 */

pragma solidity ^0.8.0;

import "./SafeBridgeSenderToEthereum.sol";
import "./interfaces/IFastBridgeSender.sol";
import "./interfaces/IFastBridgeReceiver.sol";
import "../libraries/MerkleHistory.sol";

/**
 * Fast Bridge Sender to Ethereum from Arbitrum
 * Counterpart of `FastBridgeReceiverOnEthereum`
 */
contract FastBridgeSenderToEthereum is SafeBridgeSenderToEthereum, IFastBridgeSender {
    // ************************************* //
    // *             Storage               * //
    // ************************************* //

    address public governor;
    IFastBridgeReceiver public fastBridgeReceiver;
    address public fastSender;
    uint256 public minBatchTime;
    uint256 public lastBatchTime;
    uint256 public expiration; // avoids mining old merkle roots. e.g. ~ 1 month [in blocks, roughly ~15 sec / block]
    MerkleHistory public merkleHistory;
    mapping(bytes32 => bool) internal registered;

    // ************************************* //
    // *              Events               * //
    // ************************************* //

    /**
     * The relayers need to watch for these events and
     * relay the message on the FastBridgeReceiverOnEthereum
     * by submitting a Merkle Proof which includes:
     *
     *  1. bytes32 merkleRoot stamped with a blocknumber
     *  2. uint256 blocknumber the merkle root is stamped with
     *  3. uint256 messageIndex to properly traverse the merkleTree
     *  4. bytes32[] proof to provide sibling hashes to verify merkleRoot
     */
    event ReceivedMessage(address indexed target, bytes32 indexed messageHash, bytes message, uint256 messageIndex);
    /**
     * The bridgers need to watch for these events and relay the
     * stamped merkleRoot on the FastBridgeReceiverOnEthereum.
     */
    event OutgoingMessageBatch(uint256 indexed blockNumber, bytes32 merkleRootStamped, bytes32 merkleRoot);
    /**
     * The off-chain proof construction code will need to update
     * it's depth parameter to pass valid merkle proofs to the FastBridgeReceiverOnEthereum.
     */
    event TreeDepthChange(uint256 newTreeDepth);

    // ************************************* //
    // *        Function Modifiers         * //
    // ************************************* //

    modifier onlyByGovernor() {
        require(governor == msg.sender, "Access not allowed: Governor only.");
        _;
    }

    constructor(
        address _governor,
        IFastBridgeReceiver _fastBridgeReceiver,
        uint256 _minBatchTime,
        uint256 _treedepth
    ) SafeBridgeSenderToEthereum() {
        governor = _governor;
        merkleHistory = new MerkleHistory(_governor, address(this), _treedepth);
        minBatchTime = _minBatchTime;
        fastBridgeReceiver = _fastBridgeReceiver;
        lastBatchTime = block.timestamp;
        expiration = 172800; // 1 month / (15 sec / block)
    }

    // ************************************* //
    // *         State Modifiers           * //
    // ************************************* //

    /**
     * Records an arbitrary message from one domain in a merkle
     * tree of batched messages to send to another domain via
     * the fast bridge mechanism
     *
     * @param _receiver The L1 contract address who will receive the calldata
     * @param _calldata The receiving domain encoded message data.
     */
    function sendFast(address _receiver, bytes memory _calldata) external override {
        require(msg.sender == fastSender, "Access not allowed: Fast Sender only.");

        // Encode the receiver address with the function signature + arguments i.e calldata
        bytes memory messageData = abi.encode(_receiver, _calldata);
        bytes32 messageHash = keccak256(messageData);

        bool success = merkleHistory.deposit(messageHash);
        if (success == false) {
            // merkleTree is full, default capacity is 2**16 = 65536 messages
            // governance should expand the size by calling setDepositContractTreeDepth(uint256)
            // fixed depth prevents second pre-image attack
            // https://flawed.net.nz/2018/02/21/attacking-merkle-trees-with-a-second-preimage-attack/
            _sendBatch();
            merkleHistory.deposit(messageHash);
        }

        emit ReceivedMessage(_receiver, messageHash, messageData, merkleHistory.depositCount());

        if (minBatchTime < block.timestamp - lastBatchTime) {
            _sendBatch();
        }
    }

    /**
     * Sends a batch of arbitrary message from one domain to another
     * via the fast bridge mechanism.
     */
    function sendBatch() public {
        require(minBatchTime < block.timestamp - lastBatchTime, "minBatchTime not elapsed.");
        _sendBatch();
    }

    /**
     * Returns deposit count in current batch of messages.
     */
    function getDepositCount() public view returns (uint256) {
        return merkleHistory.depositCount();
    }

    /**
     * Sends a batch of arbitrary message from one domain to another
     * via the fast bridge mechanism.
     */
    function _sendBatch() internal {
        bytes32 merkleRoot = merkleHistory.get_deposit_root();
        merkleHistory.reset();
        lastBatchTime = block.timestamp;

        bytes memory merkleRootStamped = abi.encode(merkleRoot, block.number);
        bytes32 merkleRootStampedHash = keccak256(merkleRootStamped);
        registered[merkleRootStampedHash] = true;

        emit OutgoingMessageBatch(block.number, merkleRootStampedHash, merkleRoot);
    }

    /**
     * Refreshes stale Merkle Root.
     * @param _blocknumber block number of old merkle root to refresh
     */
    function sendRefresh(uint256 _blocknumber) external {
        bytes32 merkleRoot = merkleHistory.get_deposit_root(_blocknumber);
        require(merkleRoot != bytes32(0), "No history for requested block number.");
        require(block.number - _blocknumber > expiration, "Merkle root is still fresh.");
        // avoids any possible collision with block.number used in _sendBatch()
        require(minBatchTime > block.timestamp - lastBatchTime, "minBatchTime not elapsed.");
        // optionally limit the number of refresh requests
        // maybe only allow on refresh request after minimum of 10 * minBatchTime
        bytes memory merkleRootStamped = abi.encode(merkleRoot, block.number);
        bytes32 merkleRootStampedHash = keccak256(merkleRootStamped);
        registered[merkleRootStampedHash] = true;

        emit OutgoingMessageBatch(block.number, merkleRootStampedHash, merkleRoot);
    }

    /**
     * Sends a merkleRoot batch of arbitrary message from one domain to another
     * via the safe bridge mechanism, which relies on the chain's native bridge.
     *
     * It is unnecessary during normal operations but essential only in case of challenge.
     *
     * It may require some ETH (or whichever native token) to pay for the bridging cost,
     * depending on the underlying safe bridge.
     *
     * @param _merkleRootStampedHash The merkle root 'stamped' (hashed) with a blocknumber corresponding to a batch of messages.
     */
    function sendSafeFallback(bytes32 _merkleRootStampedHash) external payable override {
        // Safe Bridge message envelope
        bytes4 methodSelector = IFastBridgeReceiver.verifySafe.selector;
        bytes memory safeMessageData = abi.encodeWithSelector(
            methodSelector,
            _merkleRootStampedHash,
            registered[_merkleRootStampedHash]
        );

        // TODO: how much ETH should be provided for bridging? add an ISafeBridgeSender.bridgingCost() if needed
        _sendSafe(address(fastBridgeReceiver), safeMessageData);
    }

    // ************************ //
    // *      Governance      * //
    // ************************ //

    function setFastSender(address _fastSender) external onlyByGovernor {
        require(fastSender == address(0), "fastSender already set.");
        fastSender = _fastSender;
    }

    function setMinBatchTime(uint256 _minBatchTime) external onlyByGovernor {
        minBatchTime = _minBatchTime;
    }

    function setExpiration(uint256 _minBatchTime) external onlyByGovernor {
        minBatchTime = _minBatchTime;
    }

    function setMerkleHistoryTreeDepth(uint256 _treeDepth) external onlyByGovernor {
        require(_treeDepth <= 32, "Tree too deep.");
        _sendBatch();
        merkleHistory.setDepositContractTreeDepth(_treeDepth);
        emit TreeDepthChange(_treeDepth);
    }
}
