// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author MichealKing(@BuildWithKing)
 * @notice This is a cross-chain rebase token that incentivizes users to deposit into a vault and earn interest in rewards.
 * @notice The interest rate in the smart contract can only decrease
 * @notice Each user will have their own interest rate, that is determined by the time they deposit into the vault.
 * @notice The earlier they deposit, the higher their interest rate will be. The later they deposit, the lower their interest rate will be.
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    // ================================== Custom Errors ===================================
    /// @notice Thrown when owner tries to set a new interest rate that is higher than the current interest rate
    /// @param currentInterestRate The current interest rate
    /// @param newInterestRate The new interest rate that was attempted to be set
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 currentInterestRate, uint256 newInterestRate);

    // ================================== State Variables ==================================
    /// @notice A constant precision factor used for calculating interest, set to 1e18 to allow for high precision in interest calculations.
    uint256 private constant PRECISION_FACTOR = 1e18;

    /// @notice The interest rate for the token, which can only decrease over time
    uint256 private s_interestRate = 5e10;

    /// @notice A constant role identifier for the mint and burn role,
    /// which is used to control access to the mint and burn functions of the token.
    bytes32 public constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    // ================================== Mappings =========================================
    /// @notice A mapping to store the interest rate for each user, which is determined by the time they deposit into the vault.
    mapping(address => uint256) private s_userInterestRate;

    /// @notice A mapping to store the last updated timestamp for each user, which is used to calculate the interest earned by the user.
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    // ================================== Events ============================================
    /// @notice Emitted when the interest rate is set
    /// @param newInterestRate The new interest rate that has been set
    event InterestRateSet(uint256 newInterestRate);

    // ================================== Constructor ======================================
    /// @notice Sets the name and symbol of the token
    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    // ================================== Modifiers =========================================
    /**
     * @notice Modifier to restrict access to functions that can only be called by accounts with the mint and burn role.
     * @dev Reverts if the caller does not have the mint and burn role.
     */
    function grantMintAndBurnRole(address _account) external onlyOwner {
        if (_account == owner()) {
            return;
        }
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    // ================================== External Write Functions ===============================
    /**
     * @notice Sets a new interest rate for the token. Callable only by the contract owner.
     * @dev The new interest rate must be less than the current interest rate, otherwise the transaction will revert with an error.
     * @param _newInterestRate The new interest rate to be set
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        // Revert if the new interest rate is higher than the current interest rate
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        // Set the new interest rate
        s_interestRate = _newInterestRate;

        // Emit an event to notify that the interest rate has been updated
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice Mints new tokens to a specified address. Callable only by the vault.
     * @param _to The address to receive the minted tokens
     * @param _amount The amount of tokens to be minted
     * @param _userInterestRate The interest rate for the user
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        // Mints accrued interest to the user before minting new tokens, to ensure that the user's interest is up to date
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = _userInterestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burns token from a specified address. Callable only by the vault.
     * @param _from The address to burn the tokens from
     * @param _amount The amount of tokens to be burned
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        // Mints accrued interest to the user before burning tokens, to ensure that the user's interest is up to date
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice Transfers tokens from one address to another.
     * @dev When transferring tokens, the accrued interest for both the sender and the recipient will be minted
     * before the transfer to ensure that their balances are up to date.
     * If the recipient does not have any tokens yet, their interest rate will be set to be the same as the sender's interest rate.
     * @param _recipient The address to receive the tokens
     * @param _amount The amount of tokens to be transferred
     * @return A boolean value indicating whether the transfer was successful
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }

        // Set the recipient's interest rate to be the same as the sender's interest rate
        // if the recipient does not have any tokens yet, which means they are new to the vault.
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfers tokens from one address to another on behalf of the sender.
     * @dev When transferring tokens, the accrued interest for both the sender and the recipient will be minted
     * before the transfer to ensure that their balances are up to date.
     * If the recipient does not have any tokens yet, their interest rate will be set to be the same as the sender's interest rate.
     * @param _sender The address of the sender
     * @param _recipient The address to receive the tokens
     * @param _amount The amount of tokens to be transferred
     * @return A boolean value indicating whether the transfer was successful
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }

        // Set the recipient's interest rate to be the same as the sender's interest rate
        // if the recipient does not have any tokens yet, which means they are new to the vault.
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    // ======================================= External Read Functions ============================
    /**
     * @notice Returns the user's current interest rate.
     * @param _user The address of the user to get the interest rate for
     * @return The current interest rate for the user
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    /**
     * @notice Returns the principle balance of the user, which does not include the interest earned since the last update.
     * @param _user The address of the user to get the principle balance for
     * @return The principle balance of the user
     */
    function getPrincipleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Returns the current interest rate for the token.
     * @return The current interest rate for the token
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    // ======================================= Public Read Functions ============================
    /**
     * @notice Returns the balance of the user, which includes the principle balance and the interest earned since the last update.
     * @param _user The address of the user to get the balance for
     * @return The current balance of the user, including interest earned since the last update.
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // Get the current tokens already minted to the user -> principle balance
        // Multiply the principle balance by the user's interest rate that has been accumulated since the last updated timestamp to get the interest earned -> interestEarned
        return super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
    }

    // ======================================= Internal Write Functions ============================
    /**
     * @notice Mints the accrued interest to the user by calculating the interest earned since the last update and minting the corresponding amount of tokens to the user.
     * @param _user The address of the user to mint the accrued interest to
     */
    function _mintAccruedInterest(address _user) internal {
        // Find the current balance of rebase tokens already minted to the user -> Principle balance
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        // Calculate their current balance including any interest -> balanceOf
        uint256 currentBalance = balanceOf(_user);
        // Calculate the number of tokens that needs to be minted to the user, which is the difference between the current balance and the principle balance -> interestToMint
        uint256 interestToMint = currentBalance - previousPrincipleBalance;
        // Set the user's last updated timestamp.
        s_userLastUpdatedTimestamp[_user] = block.timestamp;

        // Call _mint to mint the token to the user
        _mint(_user, interestToMint);
    }

    /**
     * @notice Calculates the user's accumulated interest.
     * @param _user The address of the user to calculate the accumulated interest for
     * @return interestAccumulated The accumulated interest for the user since the last update.
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 interestAccumulated)
    {
        // We need to calculate the interest that has been accumulated since the last update.
        // This is going to be linear growth with time
        // 1. Calculate the time since the last update
        // 2. Calculate the amount of linear growth
        // Principle amount (1 *( interest rate * time since last update)
        uint256 timeSinceLastUpdate = block.timestamp - s_userLastUpdatedTimestamp[_user];
        interestAccumulated = PRECISION_FACTOR + (s_userInterestRate[_user] * timeSinceLastUpdate);
    }
}
