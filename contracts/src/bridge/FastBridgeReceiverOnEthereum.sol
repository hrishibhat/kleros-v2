// SPDX-License-Identifier: MIT

/**
 *  @authors: [@jaybuidl, @shalzz, @hrishibhat, @shotaronowhere]
 *  @reviewers: []
 *  @auditors: []
 *  @bounties: []
 *  @deployments: []
 */

pragma solidity ^0.8.0;

import "./SafeBridgeReceiverOnEthereum.sol";
import "./interfaces/IFastBridgeReceiver.sol";
import "../libraries/MerkleArbitrum.sol";

/**
 * Fast Bridge Receiver on Ethereum from Arbitrum
 * Counterpart of `FastBridgeSenderToEthereum`
 */
contract FastBridgeReceiverOnEthereum is SafeBridgeReceiverOnEthereum, IFastBridgeReceiver {
    using MerkleArbitrum for bytes32[];
    // ************************************* //
    // *         Enums / Structs           * //
    // ************************************* //

    struct Claim {
        address bridger;
        uint256 claimedAt;
        uint256 claimDeposit;
        bool honest;
    }

    struct Challenge {
        address challenger;
        uint256 challengedAt;
        uint256 challengeDeposit;
        bool honest;
    }    

    // ************************************* //
    // *             Storage               * //
    // ************************************* //

    uint256 public override claimDeposit;
    uint256 public override challengeDeposit;
    uint256 public override challengeDuration;
    uint256 public override expirationTime;              // avoids mining old merkle roots. e.g. ~ 1 month
    uint256 public override claimPeriod;                 // should be <= minBatchTime
    uint256 public timeClaimPeriodSet;          // time to start claim count
    uint256 public claimAllowance;              // memory when claimPeriod is reset
    uint256 public totalClaims;
    mapping(bytes32 => Claim) public claims; // merkleRoot => claim
    mapping(bytes32 => Challenge) public challenges; // merkleRoot => challenge

    mapping(bytes32 => bool) public relayed; //  uniqueMessageID => relayed

    // ************************************* //
    // *              Events               * //
    // ************************************* //

    event ClaimReceived(bytes32 indexed messageHash, uint256 claimedAt);
    event ClaimChallenged(bytes32 indexed _messageHash, uint256 challengedAt);


    constructor(
        address _governor,
        address _safeBridgeSender,
        address _inbox,
        uint256 _claimDeposit,
        uint256 _challengeDeposit,
        uint256 _challengeDuration,
        uint256 _expirationTime,
        uint256 _claimPeriod
    ) SafeBridgeReceiverOnEthereum(_governor, _safeBridgeSender, _inbox) {
        claimDeposit = _claimDeposit;
        challengeDeposit = _challengeDeposit;
        challengeDuration = _challengeDuration;
        expirationTime = _expirationTime;
        claimPeriod = _claimPeriod;
        timeClaimPeriodSet = block.timestamp;
        totalClaims = 0;
    }

    // ************************************* //
    // *         State Modifiers           * //
    // ************************************* //

    function claim(bytes32 _merkleRootStampedHash) external payable override {
        require(msg.value >= claimDeposit, "Not enough claim deposit");
        require(totalClaims < getClaimAllowance(), "Too many claims.");
        require(claims[_merkleRootStampedHash].bridger == address(0), "Claimed already made");

        claims[_merkleRootStampedHash] = Claim({
            bridger: msg.sender,
            claimedAt: block.timestamp,
            claimDeposit: msg.value,
            honest: false
        });

        totalClaims += 1;
        emit ClaimReceived(_merkleRootStampedHash, block.timestamp);
    }

    function getClaimAllowance() view internal returns (uint256){
        return (block.timestamp - timeClaimPeriodSet)/claimPeriod + claimAllowance;
    }

    function challenge(bytes32 _merkleRootStampedHash) external payable override {
        Claim memory claim = claims[_merkleRootStampedHash];
        require(claim.bridger != address(0), "Claim does not exist");        
        require(block.timestamp - claim.claimedAt <  challengeDuration, "Challenge period over");
        require(msg.value >= challengeDeposit, "Not enough challenge deposit");
        require(challenges[_merkleRootStampedHash].challenger == address(0), "Claim already challenged");

        challenges[_merkleRootStampedHash] = Challenge({
            challenger: msg.sender,
            challengedAt: block.timestamp,
            challengeDeposit: msg.value,
            honest: false
        });

        emit ClaimChallenged(_merkleRootStampedHash, block.timestamp);
    }

    /**
     * Receives an individual arbitrary message from fast bridge sender
     * via the safe bridge mechanism, which relies on the chain's native bridge.
     *
     * It is unnecessary during normal operations but an optional feature.
     * Allows messages to be relayed if the merkleRoot associated with the message
     * is stale, and the message was not relayed while the merkleRoot was active.
     *
     * @param _encodedData The data encoding receiver, function selector, and calldata
     */
    function verifyAndRelay(bytes32 _merkleRootStampedHash, uint256 blocknumberStamp, bytes32[] memory proof, uint256 index, bytes memory _encodedData) external override{
        Claim storage claim = claims[_merkleRootStampedHash];
        Challenge storage challenge = challenges[_merkleRootStampedHash];

        require(claim.bridger != address(0), "Claim does not exist");
        require(block.timestamp - claim.claimedAt < challengeDuration + expirationTime, "Merkle Root is stale.");
        require(claim.claimedAt + challengeDuration < block.timestamp, "Challenge period not over");
        require((claim.honest == true) || (challenge.challenger == address(0)), "Claim not proven.");
        bytes32 messageHash = keccak256(_encodedData);
        bytes32 uniqueMessageID = keccak256(abi.encode(proof, index, messageHash, _merkleRootStampedHash));
        require(relayed[uniqueMessageID] == false, "Message already relayed");

        bytes32 merkleRoot = proof.calculateRoot(index, messageHash);
        require(_merkleRootStampedHash == keccak256(abi.encode(merkleRoot,blocknumberStamp)), "Invalid proof.");


        // Decode the receiver address from the data encoded by the IFastBridgeSender
        (address receiver, bytes memory data) = abi.decode(_encodedData, (address, bytes));
        (bool success, ) = address(receiver).call(data);
        require(success, "Failed to call contract");

        relayed[uniqueMessageID] = true;
    }

    /**
     * Receives a validity boolean and merkle root which represents arbitrary 
     * messages from fast bridge sender via the safe bridge mechanism, 
     * which relies on the chain's native bridge.
     *
     * If valid, any claim is proven honest.
     * 
     * If invalid, any challenge is proven honest.
     *
     * @param _merkleRootStampedHash The merkleRootStampedHash requested for validation by safe bridge
     * @param _isValid The validity of _merkleRootStampedHash.
     */
    function verifySafe(bytes32 _merkleRootStampedHash, bool _isValid) override external {
        require(isSentBySafeBridge(), "Access not allowed: SafeBridgeSender only.");

        Challenge storage challenge = challenges[_merkleRootStampedHash];
        Claim storage claim = claims[_merkleRootStampedHash];

        if(_isValid == true){
            claim.honest = true;
            if(claim.bridger == address(0)){
                // no claim, set as safe bridge
                claim.bridger = safeBridgeSender;
                claim.claimedAt = block.timestamp;
            }
        } else if(challenge.challenger != address(0)){
                challenge.honest = true;
        }
    }

    function withdrawClaimDeposit(bytes32 _merkleRootStampedHash) external override {
        Claim storage claim = claims[_merkleRootStampedHash];
        Challenge storage challenge = challenges[_merkleRootStampedHash];
        require(claim.bridger != address(0), "Claim does not exist");
        require(block.timestamp - challenge.challengedAt > challengeDuration, "Challenge period not over yet.");
        require((claim.honest == true) || (challenge.challenger == address(0)), "Claim not proven.");
        uint256 amount = claim.claimDeposit;
        if(claim.honest == true)
            amount += challenge.challengeDeposit;
        claim.claimDeposit = 0;
        challenge.challengeDeposit = 0;
        payable(claim.bridger).send(amount);
    }

    function withdrawChallengeDeposit(bytes32 _merkleRootStampedHash) external override {
        Challenge storage challenge = challenges[_merkleRootStampedHash];
        require(challenge.challenger != address(0), "Challenge does not exist");
        require(challenge.honest == true, "Challenge not proven.");
        uint256 amount = challenge.challengeDeposit + claims[_merkleRootStampedHash].claimDeposit;
        challenge.challengeDeposit = 0;
        claims[_merkleRootStampedHash].claimDeposit = 0;
        payable(challenge.challenger).send(amount);
    }

    // ************************************* //
    // *           Public Views            * //
    // ************************************* //

    function challengePeriod(bytes32 _messageHash) public view returns (uint256 start, uint256 end) {
        Claim storage claim = claims[_messageHash];
        require(claim.bridger != address(0), "Claim does not exist");

        start = claim.claimedAt;
        end = start + challengeDuration;
        return (start, end);
    }

    // ************************ //
    // *      Governance      * //
    // ************************ //

    function setClaimDeposit(uint256 _claimDeposit) external onlyByGovernor {
        claimDeposit = _claimDeposit;
    }

    function setChallengeDeposit(uint256 _challengeDeposit) external onlyByGovernor {
        challengeDeposit = _challengeDeposit;
    }

    function setChallengePeriodDuration(uint256 _challengeDuration) external onlyByGovernor {
        challengeDuration = _challengeDuration;
    }

    function setClaimPeriod(uint256 _claimPeriod) external onlyByGovernor {
        claimPeriod = _claimPeriod;
        claimAllowance += getClaimAllowance();
        timeClaimPeriodSet = block.timestamp;
    }

    function setExpirationTime(uint256 _expirationTime) external onlyByGovernor {
        expirationTime = _expirationTime;
    }
}
