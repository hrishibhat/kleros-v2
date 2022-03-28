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
    MerkleHistory public merkleHistory;
    mapping (bytes32 => bool) internal registered;

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
     * The bridgers need to watch for these events and relay the 
     * stamped merkleRoot on the FastBridgeReceiverOnEthereum.
     */
    event TreeDepthChange(uint256 newTreeDepth);

    // ************************************* //
    // *        Function Modifiers         * //
    // ************************************* //

    modifier onlyByGovernor() {
        require(governor == msg.sender, "Access not allowed: Governor only.");
        _;
    }

    constructor(address _governor, uint256 _minBatchTime) SafeBridgeSenderToEthereum() {
        governor = _governor;
        merkleHistory = new MerkleHistory(_governor, address(this));
        minBatchTime = _minBatchTime;
        lastBatchTime = block.timestamp;
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
        if (success == false){
            // merkleTree is full, default capacity is 2**16-1 = 65535 messages
            // governance should expand the size by calling setDepositContractTreeDepth(uint256)
            _sendBatch();
            merkleHistory.deposit(messageHash);
        }

        emit ReceivedMessage(_receiver, messageHash, messageData, merkleHistory.depositCount());

        if(minBatchTime < block.timestamp + lastBatchTime){
            _sendBatch();
        }
    }

    /**
     * Sends an arbitrary message from one domain to another
     * via the fast bridge mechanism
     *
     */
    function sendBatch() public {
        require(minBatchTime < block.timestamp + lastBatchTime, "minBatchTime not elapsed.");
        _sendBatch();
    }

    function getDepositCount() public view returns (uint256){
        return merkleHistory.depositCount();
    }

    function _sendBatch() internal {
        bytes32 merkleRoot = merkleHistory.get_deposit_root();
        merkleHistory.reset();
        
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
    function sendSafeFallback(bytes32 _merkleRootStampedHash) override external payable {
    
        // Safe Bridge message envelope
        bytes4 methodSelector = IFastBridgeReceiver.verifySafe.selector;
        bytes memory safeMessageData = abi.encodeWithSelector(methodSelector, _merkleRootStampedHash, registered[_merkleRootStampedHash]);

        // TODO: how much ETH should be provided for bridging? add an ISafeBridgeSender.bridgingCost() if needed
        _sendSafe(address(fastBridgeReceiver), safeMessageData);
    }

    // ************************ //
    // *      Governance      * //
    // ************************ //

    function setFastBridgeReceiver(IFastBridgeReceiver _fastBridgeReceiver) external onlyByGovernor {
        require(address(fastBridgeReceiver) == address(0), "fastSender already set.");
        fastBridgeReceiver = _fastBridgeReceiver;
    }

    function setFastSender(address _fastSender) external onlyByGovernor {
        require(fastSender == address(0), "fastSender already set.");
        fastSender = _fastSender;
    }

    function setMinBatchTime(uint256 _minBatchTime) external onlyByGovernor {
        minBatchTime = _minBatchTime;
    }

    function setMerkleHistoryTreeDepth(uint256 _treeDepth) external onlyByGovernor{
        require(_treeDepth <= 32, "Tree too deep.");
        _sendBatch();
        merkleHistory.setDepositContractTreeDepth(_treeDepth);
        emit TreeDepthChange(_treeDepth);
    }

}
