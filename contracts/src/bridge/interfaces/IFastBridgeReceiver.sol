// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFastBridgeReceiver {
    function claim(bytes32 _merkleRootStampedHash) external payable;

    function challenge(bytes32 _merkleRootStampedHash) external payable;

    function verifyAndRelay(bytes32 _merkleRootStamped, uint256 blocknumberStamp, bytes32[] memory proof, uint256 index, bytes memory _encodedData) external;

    function verifySafe(bytes32 _merkleRootStamped, bool isValid) external;

    function withdrawClaimDeposit(bytes32 _merkleRootStampedHash) external;

    function withdrawChallengeDeposit(bytes32 _merkleRootStampedHash) external;

    function claimDeposit() external view returns (uint256 amount);

    function challengeDeposit() external view returns (uint256 amount);

    function challengeDuration() external view returns (uint256 amount);

    function claimPeriod() external view returns (uint256 amount);

    function expirationTime() external view returns (uint256 amount);

}
