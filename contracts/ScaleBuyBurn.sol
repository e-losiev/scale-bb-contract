// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./interfaces/IERC20Burnable.sol";
import "./lib/constants.sol";

/// @title Scale Buy & Burn Contract
contract ScaleBuyBurn is Ownable2Step {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Burnable;

    // -------------------------- STATE VARIABLES -------------------------- //

    /// @notice The total amount of ELMNT tokens used in Buy & Burn to date.
    uint256 public totalE280Used;
    /// @notice The total amount of Element 280 tokens burned to date.
    uint256 public totalScaleBurned;

    /// @notice Incentive fee amount, measured in basis points (100 bps = 1%).
    uint16 public incentiveFeeBps = 30;
    /// @notice The maximum amount of E280 that can be swapped per Buy & Burn.
    uint256 public capPerSwapE280 = 800_000_000 ether;
    /// @notice The maximum amount of DragonX/E280 that can be swapped per Buy & Burn.
    uint256 public capPerSwapDragonX = 2_000_000_000 ether;
    /// @notice Cooldown for Buy & Burns in seconds.
    uint32 public buyBurnInterval = 8 hours;
    /// @notice Time of the last Buy & Burn in seconds.
    uint256 public lastBuyBurn;

    /// @notice Whitelisted addresses to run Buy & Burn.
    mapping(address account => bool) public whitelisted;

    // ------------------------------- EVENTS ------------------------------ //

    event BuyBurn();
    event ContractActivated();

    // ------------------------------- ERRORS ------------------------------ //

    error Prohibited();
    error Cooldown();
    error NoAllocation();

    // ----------------------------- CONSTRUCTOR --------------------------- //

    constructor(address _owner) Ownable(_owner) {}

    // --------------------------- PUBLIC FUNCTIONS ------------------------ //

    /// @notice Buys and burns Scale tokens using Element 280 and DragonX balance.
    /// @param minScaleAmount The minimum amount out for ELMT -> SCALE swap.
    /// @param minE280Amount The minimum amount out for the DragonX -> ELMNT swap (if applicalbe).
    /// @param deadline The deadline for the swaps.
    function buyAndBurn(uint256 minScaleAmount, uint256 minE280Amount, uint256 deadline) external {
        if (!whitelisted[msg.sender]) revert Prohibited();
        if (block.timestamp < lastBuyBurn + buyBurnInterval) revert Cooldown();

        lastBuyBurn = block.timestamp;
        uint256 e280Balance = IERC20(E280).balanceOf(address(this));
        if (e280Balance < capPerSwapE280) {
            e280Balance = _handleDragonXBalanceCheck(e280Balance, minE280Amount, deadline);
        }
        if (e280Balance == 0) revert NoAllocation();
        uint256 amountToSwap = e280Balance > capPerSwapE280 ? capPerSwapE280 : e280Balance;
        totalE280Used += amountToSwap;
        amountToSwap = _processIncentiveFee(amountToSwap);
        _swapELMNTforScale(amountToSwap, minScaleAmount, deadline);
        burnScale();
        emit BuyBurn();
    }

    /// @notice Burns all Scale tokens owned by Buy & Burn contractt.
    function burnScale() public {
        IERC20Burnable scale = IERC20Burnable(SCALE);
        uint256 amountToBurn = scale.balanceOf(address(this));
        scale.burn(amountToBurn);
        totalScaleBurned += amountToBurn;
    }

    // ----------------------- ADMINISTRATIVE FUNCTIONS -------------------- //

    /// @notice Sets the incentive fee basis points (bps) for Buy & Burns.
    /// @param bps The incentive fee in basis points (30 - 500), (100 bps = 1%).
    function setIncentiveFee(uint16 bps) external onlyOwner {
        if (bps < 30 || bps > 500) revert Prohibited();
        incentiveFeeBps = bps;
    }

    /// @notice Sets the Buy & Burn interval.
    /// @param limit The new interval in seconds.
    function setBuyBurnInterval(uint32 limit) external onlyOwner {
        if (limit == 0) revert Prohibited();
        buyBurnInterval = limit;
    }

    /// @notice Sets the cap per swap for ELMT -> SCALE swaps.
    /// @param limit The new cap limit in WEI applied to ELMNT balance.
    function setCapPerSwapE280(uint256 limit) external onlyOwner {
        capPerSwapE280 = limit;
    }

    /// @notice Sets the cap per swap for DragonX -> ELMNT swaps.
    /// @param limit The new cap limit in WEI applied to DragonX balance.
    function setCapPerSwapDragonX(uint256 limit) external onlyOwner {
        capPerSwapDragonX = limit;
    }

    /// @notice Sets the whitelist status for provided addresses for Buy & Burn.
    /// @param accounts List of wallets which status will be changed.
    /// @param isWhitelisted Status to be set.
    function setWhitelisted(address[] calldata accounts, bool isWhitelisted) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            whitelisted[accounts[i]] = isWhitelisted;
        }
    }

    // ---------------------------- VIEW FUNCTIONS ------------------------- //

    function getBuyBurnParams()
        public
        view
        returns (bool additionalSwap, uint256 nextE280Swap, uint256 nextDragonXSwap, uint256 nextBuyBurn)
    {
        uint256 e280Balance = IERC20(E280).balanceOf(address(this));
        uint256 dragonxBalance = IERC20(DRAGONX).balanceOf(address(this));
        additionalSwap = e280Balance < capPerSwapE280 && dragonxBalance > 0;
        nextE280Swap = e280Balance > capPerSwapE280 ? capPerSwapE280 : e280Balance;
        nextDragonXSwap = dragonxBalance > capPerSwapDragonX ? capPerSwapDragonX : dragonxBalance;
        nextBuyBurn = lastBuyBurn + buyBurnInterval;
    }

    // -------------------------- INTERNAL FUNCTIONS ----------------------- //

   function _handleDragonXBalanceCheck(uint256 currentE280Balance, uint256 minE280Amount, uint256 deadline)
        internal
        returns (uint256)
    {
        uint256 dragonxBalance = IERC20(DRAGONX).balanceOf(address(this));
        if (dragonxBalance == 0) return currentE280Balance;
        uint256 amountToSwap = dragonxBalance > capPerSwapDragonX ? capPerSwapDragonX : dragonxBalance;
        uint256 swappedAmount = _swapDragonXforELMNT(amountToSwap, minE280Amount, deadline);
        return currentE280Balance + swappedAmount;
    }

    function _processIncentiveFee(uint256 titanXAmount) internal returns (uint256) {
        uint256 incentiveFee = titanXAmount * incentiveFeeBps / BPS_BASE;
        IERC20(E280).safeTransfer(msg.sender, incentiveFee);
        unchecked {
            return titanXAmount - incentiveFee;
        }
    }

    function _swapELMNTforScale(uint256 amountIn, uint256 minAmountOut, uint256 deadline) internal {
        IERC20(E280).safeIncreaseAllowance(UNISWAP_V2_ROUTER, amountIn);

        address[] memory path = new address[](2);
        path[0] = E280;
        path[1] = SCALE;

        IUniswapV2Router02(UNISWAP_V2_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, minAmountOut, path, address(this), deadline
        );
    }

    function _swapDragonXforELMNT(uint256 amountIn, uint256 minAmountOut, uint256 deadline) internal returns (uint256) {
        IERC20(DRAGONX).safeIncreaseAllowance(UNISWAP_V2_ROUTER, amountIn);

        address[] memory path = new address[](2);
        path[0] = DRAGONX;
        path[1] = E280;

        uint256[] memory amounts =  IUniswapV2Router02(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
            amountIn, minAmountOut, path, address(this), deadline
        );

        return amounts[1];
    }
}