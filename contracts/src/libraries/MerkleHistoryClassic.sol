// ┏━━━┓━┏┓━┏┓━━┏━━━┓━━┏━━━┓━━━━┏━━━┓━━━━━━━━━━━━━━━━━━━┏┓━━━━━┏━━━┓━━━━━━━━━┏┓━━━━━━━━━━━━━━┏┓━
// ┃┏━━┛┏┛┗┓┃┃━━┃┏━┓┃━━┃┏━┓┃━━━━┗┓┏┓┃━━━━━━━━━━━━━━━━━━┏┛┗┓━━━━┃┏━┓┃━━━━━━━━┏┛┗┓━━━━━━━━━━━━┏┛┗┓
// ┃┗━━┓┗┓┏┛┃┗━┓┗┛┏┛┃━━┃┃━┃┃━━━━━┃┃┃┃┏━━┓┏━━┓┏━━┓┏━━┓┏┓┗┓┏┛━━━━┃┃━┗┛┏━━┓┏━┓━┗┓┏┛┏━┓┏━━┓━┏━━┓┗┓┏┛
// ┃┏━━┛━┃┃━┃┏┓┃┏━┛┏┛━━┃┃━┃┃━━━━━┃┃┃┃┃┏┓┃┃┏┓┃┃┏┓┃┃━━┫┣┫━┃┃━━━━━┃┃━┏┓┃┏┓┃┃┏┓┓━┃┃━┃┏┛┗━┓┃━┃┏━┛━┃┃━
// ┃┗━━┓━┃┗┓┃┃┃┃┃┃┗━┓┏┓┃┗━┛┃━━━━┏┛┗┛┃┃┃━┫┃┗┛┃┃┗┛┃┣━━┃┃┃━┃┗┓━━━━┃┗━┛┃┃┗┛┃┃┃┃┃━┃┗┓┃┃━┃┗┛┗┓┃┗━┓━┃┗┓
// ┗━━━┛━┗━┛┗┛┗┛┗━━━┛┗┛┗━━━┛━━━━┗━━━┛┗━━┛┃┏━┛┗━━┛┗━━┛┗┛━┗━┛━━━━┗━━━┛┗━━┛┗┛┗┛━┗━┛┗┛━┗━━━┛┗━━┛━┗━┛
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┃┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┗┛━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// Modified from:
// https://github.com/ethereum/consensus-specs/blob/master/solidity_deposit_contract/deposit_contract.sol
// https://github.com/ethereum/consensus-specs/blob/master/specs/phase0/deposit-contract.md
// Modification by @shotaronowhere
// Modified to maintain history of merkle roots and support simple bytes32 message hashes as leaves

// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.0;

// This interface is designed to be compatible with the Vyper version.
/// @notice This is the Ethereum 2.0 deposit contract interface.
/// For more information see the Phase 0 specification under https://github.com/ethereum/eth2.0-specs
interface IDepositContract {
    /// @notice A processed deposit event.
    event DepositEvent(
        bytes32 message,
        uint256 index
    );

    /// @notice Submit a Fast message.
    /// @param message a fast message.
    function deposit(
        bytes32 message
    ) external returns (bool);

    /// @notice Query the current deposit root hash.
    /// @return The deposit root hash.
    function get_deposit_root() external view returns (bytes32);

    /// @notice Query the current deposit count.
    /// @return The deposit count encoded as a little endian 64-bit number.
    function depositCount() external view returns (uint256);
}

// Based on official specification in https://eips.ethereum.org/EIPS/eip-165
interface ERC165 {
    /// @notice Query if a contract implements an interface
    /// @param interfaceId The interface identifier, as specified in ERC-165
    /// @dev Interface identification is specified in ERC-165. This function
    ///  uses less than 30,000 gas.
    /// @return `true` if the contract implements `interfaceId` and
    ///  `interfaceId` is not 0xffffffff, `false` otherwise
    function supportsInterface(bytes4 interfaceId) external pure returns (bool);
}

// This is a rewrite of the Vyper Eth2.0 deposit contract in Solidity.
// It tries to stay as close as possible to the original source code.
/// @notice This is the Ethereum 2.0 deposit contract interface.
/// For more information see the Phase 0 specification under https://github.com/ethereum/eth2.0-specs
contract MerkleHistoryClassic is IDepositContract, ERC165 {
    uint256 public depositContractTreeDepth;
    uint256 public maxDepositCount;

    bytes32[32] internal branch;
    // blocknumber => merkleRoot
    mapping(uint256 => bytes32) public history;
    uint256 public override depositCount;
    address public governor;
    address public fastBridge;
    bytes32[32] internal zero_hashes;

    // ************************************* //
    // *        Function Modifiers         * //
    // ************************************* //

    modifier onlyByGovernor() {
        require(governor == msg.sender, "Access not allowed: Governor only.");
        _;
    }

    modifier onlyByFastBridge() {
        require(fastBridge == msg.sender, "Access not allowed: Governor only.");
        _;
    }
    constructor(address _governor, address _fastBridge, uint256 _treeDepth) {
        governor = _governor;
        fastBridge = _fastBridge;
        require(_treeDepth <= 32, "Tree too deep.");
        depositContractTreeDepth = _treeDepth;
        maxDepositCount = 2**depositContractTreeDepth - 1;
        // Compute hashes in empty sparse Merkle tree
        for (uint height = 0; height <  31; height++)
            zero_hashes[height + 1] = keccak256(abi.encodePacked(zero_hashes[height], zero_hashes[height]));
    }

    // ************************************* //
    // *         State Modifiers           * //
    // ************************************* //


    function get_deposit_root() override public view returns (bytes32) {
        bytes32 node;
        uint size = depositCount;
        for (uint height = 0; height < depositContractTreeDepth; height++) {
            if ((size & 1) == 1)
                node = keccak256(abi.encodePacked(branch[height], node));
            else
                node = keccak256(abi.encodePacked(node, zero_hashes[height]));
            size /= 2;
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
    ) override external returns (bool){
        // Avoid overflowing the Merkle tree (and prevent edge case in computing `branch`)
        if(depositCount >= maxDepositCount){
            //DepositContract: merkle tree full
            return false;
        }

        // Add deposit data root to Merkle tree (update a single `branch` node)
        depositCount += 1;
        uint size = depositCount;
        for (uint height = 0; height < depositContractTreeDepth; height++) {
            if ((size & 1) == 1) {
                branch[height] = message;
                return true;
            }
            message = keccak256(abi.encodePacked(branch[height], message));
            size /= 2;
        }

        // As the loop should always end prematurely with the `return` statement,
        // this code should be unreachable. We assert `false` just to be safe.
        assert(false);
        return false;
    }

    function supportsInterface(bytes4 interfaceId) override external pure returns (bool) {
        return interfaceId == type(ERC165).interfaceId || interfaceId == type(IDepositContract).interfaceId;
    }
    
    function reset() external onlyByFastBridge {
        history[block.number]=get_deposit_root();
        delete branch;
        depositCount = 0;
    }

    // ************************ //
    // *      Governance      * //
    // ************************ //

    function setDepositContractTreeDepth(uint256 _depositContractTreeDepth) external onlyByGovernor {
        require(depositContractTreeDepth <= 32, "Tree too deep.");
        require(depositCount == 0 , "Reset the tree first");
        depositContractTreeDepth = _depositContractTreeDepth;
        maxDepositCount = 2**depositContractTreeDepth - 1;
    }
}
