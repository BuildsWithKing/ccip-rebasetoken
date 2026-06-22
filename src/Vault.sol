// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";

/**
 * @title Vault
 * @author MichealKing(@BuildWithKing)
 * @notice This contract serves as a vault for the RebaseToken, allowing users to deposit and withdraw tokens.
 */
contract Vault {
    // =================================== Custom Errors =======================================
    /**
     * @notice Thrown when a user tries to redeem more tokens than they have
     * @param user The address of the user who tried to redeem more tokens than they have
     * @param amount The amount of tokens that the user tried to redeem
     */
    error Vault__RedeemFailed(address user, uint256 amount);

    // =================================== State Variables =======================================
    /// @notice The address of the RebaseToken contract
    IRebaseToken private immutable i_rebaseToken;

    // =================================== Events =======================================
    /**
     * @notice Emitted when a user deposits Ether into the vault
     * @param _user The address of the user who deposited Ether
     * @param _amount The amount of Ether deposited
     */
    event Deposit(address indexed _user, uint256 _amount);

    /**
     * @notice Emitted when a user redeems tokens from the vault
     * @param _user The address of the user who redeemed tokens
     * @param _amount The amount of tokens redeemed
     */
    event Redeem(address indexed _user, uint256 _amount);

    // =================================== Constructor =======================================
    /**
     * @notice Sets the address of the RebaseToken contract
     * @param _rebaseToken The address of the RebaseToken contract
     */
    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    // =================================== Receive Function =======================================
    /// @notice Allows the contract to receive Ether
    receive() external payable {}

    // =================================== External Write Functions =======================================
    /**
     * @notice Allows users to deposit Ether into the vault and mint corresponding RebaseTokens
     */
    function deposit() external payable {
        i_rebaseToken.mint(msg.sender, msg.value, i_rebaseToken.getInterestRate());
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Redeems tokens from the vault
     * @param _amount The amount of tokens to redeem
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }

        i_rebaseToken.burn(msg.sender, _amount);
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed(msg.sender, _amount);
        }

        emit Redeem(msg.sender, _amount);
    }

    // =================================== External Read Functions =======================================
    /**
     * @notice Returns the address of the RebaseToken contract
     * @return The address of the RebaseToken contract
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
