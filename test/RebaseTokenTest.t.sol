//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {Vault} from "src/Vault.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract RebaseTokenTest is Test {
    error ETH_TRANSFER_FAILED();

    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    uint256 public constant ETH_AMOUNT = 1e18;
    uint256 public constant MINIMUM_AMOUNT = 1e5;

    function setUp() public {
        vm.deal(owner, ETH_AMOUNT);

        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        (bool success,) = payable(address(vault)).call{value: ETH_AMOUNT}("");
        if (!success) {
            revert ETH_TRANSFER_FAILED();
        }
        vm.stopPrank();
    }

    function addRewardToken(uint256 rewardToken) private {
        (bool success,) = payable(address(vault)).call{value: rewardToken}("");
        if (!success) {
            revert ETH_TRANSFER_FAILED();
        }
    }

    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, MINIMUM_AMOUNT, type(uint96).max);
        // 1. Deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        // 2. Check shares and balance
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("Start Balance:", startBalance);
        assertEq(startBalance, amount);

        // 3. Warp the time
        vm.warp(block.timestamp + 1 hours);
        // 4. Check shares and balance after time warp
        uint256 middleBalance = rebaseToken.balanceOf(user);
        console.log("Middle Balance:", middleBalance);
        assertGt(middleBalance, startBalance);

        // 5. Warp the time again
        vm.warp(block.timestamp + 1 hours);
        // 6. Check shares and balance after second time warp
        uint256 endBalance = rebaseToken.balanceOf(user);
        console.log("End Balance:", endBalance);
        assertGt(endBalance, middleBalance);

        uint256 profit = middleBalance - startBalance;
        uint256 profit2 = endBalance - middleBalance;

        assertApproxEqAbs(profit, profit2, 1);
        vm.stopPrank();
    }

    function testRedeem(uint256 amount) public {
        amount = bound(amount, MINIMUM_AMOUNT, type(uint96).max);
        // 1. Deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);

        // 2. Redeem
        vault.redeem(type(uint256).max);
        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(user.balance, amount);
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 amount, uint256 time) public {
        time = bound(time, 10000, type(uint96).max);
        amount = bound(amount, MINIMUM_AMOUNT, type(uint96).max);

        // 1. Deposit
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        // 2. Warp the time
        vm.warp(block.timestamp + time);

        uint256 balance = rebaseToken.balanceOf(user);

        // Add rewards to the vault.
        vm.deal(owner, balance - amount);
        vm.prank(owner);
        addRewardToken(balance - amount);

        console.log("Balance after time warp:", rebaseToken.balanceOf(user));

        // 3. Redeem
        vm.prank(user);
        vault.redeem(type(uint256).max);

        console.log("Balance after redeem:", rebaseToken.balanceOf(user));

        uint256 userEthBalance = address(user).balance;

        assertEq(userEthBalance, balance);
        assertGt(userEthBalance, amount);
    }

    function testTransfer(uint256 amount, uint256 amountToTransfer) public {
        amount = bound(amount, MINIMUM_AMOUNT + MINIMUM_AMOUNT, type(uint96).max);
        amountToTransfer = bound(amountToTransfer, MINIMUM_AMOUNT, amount - MINIMUM_AMOUNT);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        uint256 userBalance = rebaseToken.balanceOf(user);
        assertEq(userBalance, amount);

        address recipient = makeAddr("recipient");
        uint256 recipientInitialBalance = rebaseToken.balanceOf(recipient);
        assertEq(recipientInitialBalance, 0);

        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        vm.prank(user);
        rebaseToken.transfer(recipient, amountToTransfer);
        uint256 recipientFinalBalance = rebaseToken.balanceOf(recipient);
        console.log("Recipient Final Balance:", recipientFinalBalance);

        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        console.log("User Balance After Transfer:", userBalanceAfterTransfer);

        assertEq(recipientFinalBalance, amountToTransfer);
        assertEq(userBalanceAfterTransfer, userBalance - amountToTransfer);

        uint256 interestRate = 5e10;

        // Check that the interest rates for both the sender and recipient are the same after the transfer
        assertEq(rebaseToken.getUserInterestRate(user), interestRate);
        assertEq(rebaseToken.getUserInterestRate(recipient), interestRate);
        assertEq(rebaseToken.getUserInterestRate(user), rebaseToken.getUserInterestRate(recipient));
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 currentInterestRate = rebaseToken.getInterestRate();

        newInterestRate = bound(newInterestRate, currentInterestRate, type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector, currentInterestRate, newInterestRate
            )
        );
        vm.prank(owner);
        rebaseToken.setInterestRate(newInterestRate);

        assertEq(rebaseToken.getInterestRate(), currentInterestRate);
    }

    function testUsersCannotSetInterestRate(uint256 newInterestRate, address randomUser) public {
        newInterestRate = bound(newInterestRate, 0, 5e10);
        vm.assume(randomUser != owner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, randomUser));
        vm.prank(randomUser);
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testUsersCannotMintOrBurnTokens(uint256 amount, address randomUser) public {
        amount = bound(amount, MINIMUM_AMOUNT, type(uint96).max);
        vm.assume(randomUser != address(vault));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, randomUser, rebaseToken.MINT_AND_BURN_ROLE()
            )
        );
        vm.prank(randomUser);
        rebaseToken.mint(randomUser, amount, rebaseToken.getUserInterestRate(randomUser));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, randomUser, rebaseToken.MINT_AND_BURN_ROLE()
            )
        );
        vm.prank(randomUser);
        rebaseToken.burn(randomUser, amount);
    }

    function testGetPrincipleBalanceOf(address randomUser, uint256 amount) public {
        amount = bound(amount, MINIMUM_AMOUNT, type(uint96).max);
        vm.assume(randomUser != address(0));

        vm.deal(randomUser, amount);
        vm.prank(randomUser);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.getPrincipleBalanceOf(randomUser), amount);

        vm.warp(block.timestamp + 1 hours);
        assertEq(rebaseToken.getPrincipleBalanceOf(randomUser), amount);
    }

    function testGetRebaseTokenAddress() public {
        address rebaseTokenAddress = vault.getRebaseTokenAddress();
        assertEq(rebaseTokenAddress, address(rebaseToken));
    }

    function testGrantAndBurnRoleCanOnlyBeGrantedByOwner(address randomUser) public {
        vm.assume(randomUser != owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, randomUser));
        vm.prank(randomUser);
        rebaseToken.grantMintAndBurnRole(randomUser);
    }

    function testApproveAndTransferFrom(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != user && recipient != address(vault) && recipient != owner);
        amount = bound(amount, MINIMUM_AMOUNT, type(uint96).max);
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);

        vm.prank(user);
        rebaseToken.approve(recipient, amount);
        uint256 recipientInitialBalance = rebaseToken.balanceOf(recipient);
        assertEq(recipientInitialBalance, 0);

        vm.prank(recipient);
        rebaseToken.transferFrom(user, recipient, amount);
        uint256 recipientFinalBalance = rebaseToken.balanceOf(recipient);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);

        assertEq(userBalanceAfterTransfer, 0);
        assertEq(recipientFinalBalance, amount);
        assertEq(rebaseToken.allowance(user, recipient), 0);
    }

    function testTransferMaxUint256(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != user && recipient != address(vault) && recipient != owner);
        amount = bound(amount, MINIMUM_AMOUNT, type(uint96).max);
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);

        vm.prank(user);
        rebaseToken.transfer(recipient, type(uint256).max);
        uint256 recipientFinalBalance = rebaseToken.balanceOf(recipient);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);

        assertEq(userBalanceAfterTransfer, 0);
        assertEq(recipientFinalBalance, amount);
    }

    function testTransferWhenRecipientBalanceIsNotZero(uint256 amount, uint256 amountToTransfer) public {
        amount = bound(amount, MINIMUM_AMOUNT + MINIMUM_AMOUNT, type(uint96).max);
        amountToTransfer = bound(amountToTransfer, MINIMUM_AMOUNT, amount - MINIMUM_AMOUNT);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        uint256 userBalance = rebaseToken.balanceOf(user);
        assertEq(userBalance, amount);

        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        address recipient = makeAddr("recipient");
        vm.deal(recipient, amount);
        vm.prank(recipient);
        vault.deposit{value: amount}();
        uint256 recipientBalance = rebaseToken.balanceOf(recipient);
        assertEq(recipientBalance, amount);

        vm.prank(user);
        rebaseToken.transfer(recipient, amountToTransfer);
        uint256 recipientFinalBalance = rebaseToken.balanceOf(recipient);
        console.log("Recipient Final Balance:", recipientFinalBalance);

        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        console.log("User Balance After Transfer:", userBalanceAfterTransfer);

        assertEq(recipientFinalBalance, amount + amountToTransfer);
        assertEq(userBalanceAfterTransfer, userBalance - amountToTransfer);

        uint256 interestRate = 5e10;

        assertEq(rebaseToken.getUserInterestRate(user), interestRate);
        assertLe(rebaseToken.getUserInterestRate(recipient), interestRate);
    }

    function testTransferFromWhenRecipientBalanceIsNotZero(uint256 amount, uint256 amountToTransfer) public {
        amount = bound(amount, MINIMUM_AMOUNT + MINIMUM_AMOUNT, type(uint96).max);
        amountToTransfer = bound(amountToTransfer, MINIMUM_AMOUNT, amount - MINIMUM_AMOUNT);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        uint256 userBalance = rebaseToken.balanceOf(user);
        assertEq(userBalance, amount);

        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        address recipient = makeAddr("recipient");
        vm.deal(recipient, amount);
        vm.prank(recipient);
        vault.deposit{value: amount}();
        uint256 recipientBalance = rebaseToken.balanceOf(recipient);
        assertEq(recipientBalance, amount);

        vm.prank(user);
        rebaseToken.approve(recipient, amountToTransfer);

        vm.prank(recipient);
        rebaseToken.transferFrom(user, recipient, amountToTransfer);
        uint256 recipientFinalBalance = rebaseToken.balanceOf(recipient);
        console.log("Recipient Final Balance:", recipientFinalBalance);

        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        console.log("User Balance After Transfer:", userBalanceAfterTransfer);

        assertEq(recipientFinalBalance, amount + amountToTransfer);
        assertEq(userBalanceAfterTransfer, userBalance - amountToTransfer);

        uint256 interestRate = 5e10;

        assertEq(rebaseToken.getUserInterestRate(user), interestRate);
        assertLe(rebaseToken.getUserInterestRate(recipient), interestRate);
    }
}
