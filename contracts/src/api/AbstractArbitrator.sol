// SPDX-License-Identifier: MIT

pragma solidity ^0.8;

import "../standard/IArbitrator.sol";

/** @title Abstract Arbitrator
 *  @dev The minimum interface for a Kleros-specific implementation of the Arbitration standard.
 *       Functions related to appeals are delegated to the DisputeKit.
 */
abstract contract AbstractArbitrator is IArbitrator {
    // Kleros-specific abstractions, not part of the standard
}
