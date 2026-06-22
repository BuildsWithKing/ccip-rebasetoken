// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

import {TokenPool} from "@ccip/contracts/pools/TokenPool.sol";
import {Pool} from "@ccip/contracts/libraries/Pool.sol";
import {IERC20} from "@openzeppelin/contracts@5.3.0/token/ERC20/IERC20.sol";

contract RebaseTokenPool is TokenPool {
    uint8 private constant TOKEN_DECIMALS = 18;

    constructor(IERC20 _token, address[] memory _allowlist, address _rmnProxy, address _router)
        TokenPool(_token, TOKEN_DECIMALS, address(0), _rmnProxy, _router)
    {}

    /// @notice Lock tokens into the pool or burn the tokens.
    /// @param lockOrBurnIn Encoded data fields for the processing of tokens on the source chain.
    /// @return lockOrBurnOut Encoded data fields for the processing of tokens on the destination chain.
    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        public
        override
        returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut)
    {
        // This validation is very important to always implement first, it helps prevent exploits.
        _validateLockOrBurn(lockOrBurnIn, "", "", 0);
        IRebaseToken tokenAddress = (IRebaseToken(address(i_token)));
        address sender = lockOrBurnIn.originalSender;
        uint256 userInterestRate = tokenAddress.getUserInterestRate(sender);
        tokenAddress.burn(address(this), lockOrBurnIn.amount);

        lockOrBurnOut = Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(userInterestRate)
        });
    }

    /// @notice Releases or mints tokens to the receiver address.
    /// @param releaseOrMintIn All data required to release or mint tokens.
    /// @return releaseOrMintOut The amount of tokens released or minted on the local chain, denominated
    /// in the local token's decimals.
    /// @dev The offRamp asserts that the balanceOf of the receiver has been incremented by exactly the number
    /// of tokens that is returned in ReleaseOrMintOutV1.destinationAmount. If the amounts do not match, the tx reverts.
    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        public
        override
        returns (Pool.ReleaseOrMintOutV1 memory)
    {
        // This validation is very important to always implement first, it helps prevent exploits.
        _validateReleaseOrMint(releaseOrMintIn, releaseOrMintIn.sourceDenominatedAmount, "");
        uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));
        IRebaseToken(address(i_token))
            .mint(releaseOrMintIn.receiver, releaseOrMintIn.sourceDenominatedAmount, userInterestRate);
        return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.sourceDenominatedAmount});
    }
}
