// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFastBridgeSender {
    /**
     * Sends an arbitrary message from one domain to another
     * via the fast bridge mechanism
     *
     * @param _receiver The L1 contract address who will receive the calldata
     * @param _calldata The receiving domain encoded message data.
     */
    function sendFast(address _receiver, bytes memory _calldata) external;

    /**
     * Sends a batch of arbitrary message from one domain to another
     * via the fast bridge mechanism
     *
     * @param _merkleRootStampedHash The merkle root hashed 'stamped' with a block number.
     */
    function sendSafeFallback(bytes32 _merkleRootStampedHash) external payable;
}
