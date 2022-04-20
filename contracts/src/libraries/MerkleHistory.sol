// SPDX-License-Identifier: MIT

/**
 *  @authors: [@shotaronowhere]
 *  @reviewers: []
 *  @auditors: []
 *  @bounties: []
 *  @deployments: []
 */

pragma solidity ^0.8.0;

contract MerkleHistory {
    bytes32[32] internal branch;
    mapping(uint256 => bytes32) public history;
    uint256 public depositCount;
    address public fastBridge;
    bytes32[32] internal zero_hashes;

    constructor(address _fastBridge) {
        fastBridge = _fastBridge;
        // Compute hashes in empty sparse Merkle tree
        for (uint height = 0; height <  31; height++)
            zero_hashes[height + 1] = keccak256(abi.encodePacked(zero_hashes[height], zero_hashes[height]));
    }

    // ************************************* //
    // *         State Modifiers           * //
    // ************************************* //


    function get_deposit_root() public pure returns (bytes32) {
        bytes32 node;
        uint256 size = depositCount;
        uint256 height = 0;
        while(size >0){
            if ((size & 1) == 1)
                node = keccak256(abi.encodePacked(branch[height], node));
            else
                node = keccak256(abi.encodePacked(node, zero_hashes[height]));
            size /= 2;
            height++;
        }
        return node;
    }

    function get_deposit_root(uint256 blockNumber) external view returns (bytes32) {
        if (blockNumber == block.number)
            return get_deposit_root();

        return history[blockNumber];
    }

    function deposit(
        bytes32 message
    ) external {
        // Add deposit data root to Merkle tree (update a single `branch` node)
        depositCount += 1;
        uint size = depositCount;
        uint height = 0;
        while(size >0){
            if ((size & 1) == 1) {
                branch[height] = message;
            }
            message = keccak256(abi.encodePacked(branch[height], message));
            size /= 2;
            height++;
        }
    }

    function reset() external {
        require(fastBridge == msg.sender, "Access not allowed: Fastbdrige only.");
        history[block.number]=get_deposit_root();
        delete branch;
        depositCount = 0;
    }

    function checkMembership(
        bytes32[] memory nodes,
        uint256 route,
        bytes32 item
    )

    function calculateRoot(
        bytes32[] memory nodes,
        uint256 route,
        bytes32 item
    ) internal pure returns (bytes32) {
        uint256 proofItems = nodes.length;
        require(proofItems <= 256);
        bytes32 h = item;
        for (uint256 i = 0; i < proofItems; i++) {
            if (route % 2 == 0) {
                h = keccak256(abi.encodePacked(h, nodes[i]));
            } else {
                h = keccak256(abi.encodePacked(nodes[i], h));
            }
            route /= 2;
        }
        return h;
    }
}
