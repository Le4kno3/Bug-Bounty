// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "interfaces/IUniswapV2ERC20.sol";
import "interfaces/IUniswapV2Router.sol";
import "interfaces/IUniversalOneSidedFarm.sol";
import "../interfaces/IFarm.sol";
import "./libraries/TransferHelper.sol";

contract FarmWrapper is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    IFarm public farm;
    IUniversalOneSidedFarm public universalOneSidedFarm;
    IUniswapV2Router public quickSwapRouter;
    IUniswapV2ERC20 public quickswapLP;
    IERC20 public token;
    IERC20 public secondaryToken;

    constructor(
        IFarm _farm,
        IUniversalOneSidedFarm _universalOneSidedFarm,
        IUniswapV2Router _quickSwapRouter,
        IUniswapV2ERC20 _quickswapLP, // WETH-cxETH
        IERC20 _token,
        IERC20 _secondaryToken
    ) {
        farm = _farm;
        universalOneSidedFarm = _universalOneSidedFarm;
        quickSwapRouter = _quickSwapRouter;
        quickswapLP = _quickswapLP;
        token = _token;
        secondaryToken = _secondaryToken;
    }

    function deposit(
        uint256 _pid,
        uint256 _amount,
        bool _userWantsToStake
    ) external nonReentrant {
        require(_amount > 0, "Input amount should be greater than 0");

        //user needs to approve for this transfer first.

        //the tokens are deposited from user to this contract
        TransferHelper.safeTransferFrom(
            address(token),
            msg.sender,
            address(this),
            _amount
        );

        // Convert from "token" to "WETH-cxETH" lp for strategy
        TransferHelper.safeApprove(
            address(token),
            address(universalOneSidedFarm),
            _amount
        );

        // For `FarmWrapper.sol` contract, I want to swap `_amount` number of `token` to the other token of `quickswapLP` pair
        // What is slippageAdjustedMinLP? Minimum LP that should be returned, if less than this value then transaction should revert.
        //@audit-ok - Why is fromToken and toToken same? becuase it is a on sided farm
        uint256 lpsReceived = universalOneSidedFarm.poolLiquidity(
            address(this),
            address(token),
            _amount,
            address(quickswapLP),
            address(token),
            1
        );
        require(lpsReceived > 0, "Error in providing liquidity");

        //validate same tracker in different contracts
        require(
            quickswapLP.balanceOf(address(this)) >= lpsReceived,
            "LPs not received in wrapper contract"
        );

        TransferHelper.safeApprove(
            address(quickswapLP),
            address(farm),
            lpsReceived
        );

        farm.depositFor(_pid, lpsReceived, msg.sender, _userWantsToStake);

        //transfer the leftover tokens to msg.sender
        uint256 leftOvertoken = token.balanceOf(address(this));

        //@audit-ok - Are these calls not vulnerable? This is a wrapper for `Farm` contract,
        //         so ideally this contract should not have any leftover tokens
        //@audit-issue - Can we send extra tokens which `this` contract owns?
        //         What if we deposted for "FrameWrapper" contract?
        if (leftOvertoken > 0) {
            TransferHelper.safeTransfer(
                address(token),
                msg.sender,
                leftOvertoken
            );
        }
        uint256 leftOverSecondaryToken = secondaryToken.balanceOf(
            address(this)
        );
        if (leftOverSecondaryToken > 0) {
            TransferHelper.safeTransfer(
                address(secondaryToken),
                msg.sender,
                leftOverSecondaryToken
            );
        }
    }

    /**
     * @notice Rescue any tokens that have not been able to processed by the contract. Can also be used to rescue LPs
     * @param _token Address of the token to be rescued
     */
    function rescueFunds(address _token) external onlyOwner nonReentrant {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(balance > 0, "Insufficient token balance");
        IERC20(_token).safeTransfer(owner(), balance);
    }
}
