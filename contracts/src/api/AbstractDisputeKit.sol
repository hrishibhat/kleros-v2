// SPDX-License-Identifier: MIT

pragma solidity ^0.8;

import "./AbstractArbitrator.sol";

/** @title Abstract Dispute Kit
 *  @dev The minimum interface allowing a client to interact with a dispute kit.
 */
abstract contract AbstractDisputeKit {
    // ************************ //
    // *       Events         * //
    // ************************ //

    /**
     * @dev To be emitted when a dispute can be appealed.
     * @param _disputeID ID of the dispute.
     * @param _arbitrable The contract which created the dispute.
     */
    event AppealPossible(uint256 indexed _disputeID, IArbitrable indexed _arbitrable);

    /**
     * @dev To be emitted when the current ruling is appealed.
     * @param _disputeID ID of the dispute.
     * @param _arbitrable The contract which created the dispute.
     */
    event AppealDecision(uint256 indexed _disputeID, IArbitrable indexed _arbitrable);

    /** @dev Raised when a contribution is made, inside fundAppeal function.
     *  @param _disputeID ID of the dispute.
     *  @param _round The round the contribution was made to.
     *  @param _choice Indicates the choice option which got the contribution.
     *  @param _contributor Caller of fundAppeal function.
     *  @param _amount Contribution amount.
     */
    event Contribution(
        uint256 indexed _disputeID,
        uint256 indexed _round,
        uint256 _choice,
        address indexed _contributor,
        uint256 _amount
    );

    /** @dev Raised when a contributor withdraws a non-zero value.
     *  @param _disputeID ID of the dispute.
     *  @param _round The round the withdrawal was made from.
     *  @param _choice Indicates the choice which contributor gets rewards from.
     *  @param _contributor The beneficiary of the withdrawal.
     *  @param _amount Total withdrawn amount, consists of reimbursed deposits and rewards.
     */
    event Withdrawal(
        uint256 indexed _disputeID,
        uint256 indexed _round,
        uint256 _choice,
        address indexed _contributor,
        uint256 _amount
    );

    /** @dev To be raised when a choice is fully funded for appeal.
     *  @param _disputeID ID of the dispute.
     *  @param _round ID of the round where the choice was funded.
     *  @param _choice The choice that just got fully funded.
     */
    event ChoiceFunded(uint256 indexed _disputeID, uint256 indexed _round, uint256 indexed _choice);

    // ************************ //
    // *       Modifiers      * //
    // ************************ //

    function fundAppeal(uint256 _disputeID, uint256 _choice) external payable virtual;

    // ************************ //
    // *        Views         * //
    // ************************ //

    function fundingStatus(uint256 _disputeID, uint256 _choice)
        external
        view
        virtual
        returns (uint256 funded, uint256 goal);

    function appealPeriod(uint256 _disputeID) public view virtual returns (uint256 start, uint256 end);
}
