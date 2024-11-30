// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./interfaces/IERC20Burnable.sol";
import "./interfaces/IHelios.sol";
import "./lib/constants.sol";

/// @title Scale Buy & Burn Contract
contract ScaleBuyBurn is Ownable2Step {
    using SafeERC20 for *;

    // -------------------------- STATE VARIABLES -------------------------- //

    /// @notice Incentive fee amount, measured in basis points (100 bps = 1%).
    uint16 public incentiveFeeBps = 30;
    /// @notice The maximum amount of E280 that can be swapped per Buy & Burn.
    uint256 public capPerSwapE280 = 800_000_000 ether;
    /// @notice The maximum amount of DragonX that can be swapped per Buy & Burn.
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
    /// @param minHeliosAmount The minimum amount out for ELMT -> Helios swap.
    /// @param minE280Amount The minimum amount out for the DragonX -> ELMNT swap (if applicalbe).
    /// @param deadline The deadline for the swaps.
    function buyAndBurn(uint256 minScaleAmount, uint256 minHeliosAmount, uint256 minE280Amount, uint256 deadline) external {
        if (!whitelisted[msg.sender]) revert Prohibited();
        if (block.timestamp < lastBuyBurn + buyBurnInterval) revert Cooldown();

        lastBuyBurn = block.timestamp;
        uint256 e280Balance = IERC20(E280).balanceOf(address(this));
        if (e280Balance < capPerSwapE280) {
            e280Balance = _handleDragonXBalanceCheck(e280Balance, minE280Amount, deadline);
        }
        if (e280Balance == 0) revert NoAllocation();
        uint256 amountToSwap = e280Balance > capPerSwapE280 ? capPerSwapE280 : e280Balance;
        amountToSwap = _processIncentiveFee(amountToSwap);
        uint256 heliosAmount = amountToSwap / 10;
        uint256 scaleAmount = amountToSwap - heliosAmount;
        _swapELMNT(SCALE, scaleAmount, minScaleAmount, deadline);
        _swapELMNT(HELIOS, heliosAmount, minHeliosAmount, deadline);
        burnTokens();
        emit BuyBurn();
    }

    /// @notice Burns all Scale and Helios tokens owned by Buy & Burn contractt.
    function burnTokens() public {
        IERC20Burnable scale = IERC20Burnable(SCALE);
        IHelios helios = IHelios(HELIOS);
        uint256 scaleBurnAmount = scale.balanceOf(address(this));
        uint256 heliosBurnAmount = helios.balanceOf(address(this));
        scale.burn(scaleBurnAmount);
        helios.userBurnTokens(heliosBurnAmount);
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

    /// @notice Returns parameters for the next Buy & Burn call.
    /// @return additionalSwap If the additional swap of DragonX -> ELMNT will be performed.
    /// @return e280Amount ELMNT amount used in the next swap.
    /// @return dragonXAmount DragonX amount used in the next swap (if additional swap is needed).
    /// @return nextAvailable Timestamp in seconds when next Buy & Burn will be available.
    function getBuyBurnParams()
        public
        view
        returns (bool additionalSwap, uint256 e280Amount, uint256 dragonXAmount, uint256 nextAvailable)
    {
        uint256 e280Balance = IERC20(E280).balanceOf(address(this));
        uint256 dragonxBalance = IERC20(DRAGONX).balanceOf(address(this));
        additionalSwap = e280Balance < capPerSwapE280 && dragonxBalance > 0;
        e280Amount = e280Balance > capPerSwapE280 ? capPerSwapE280 : e280Balance;
        dragonXAmount = dragonxBalance > capPerSwapDragonX ? capPerSwapDragonX : dragonxBalance;
        nextAvailable = lastBuyBurn + buyBurnInterval;
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
        unchecked {
            return currentE280Balance + swappedAmount;
        }
    }

    function _processIncentiveFee(uint256 e280Amount) internal returns (uint256) {
        uint256 incentiveFee = e280Amount * incentiveFeeBps / BPS_BASE;
        IERC20(E280).safeTransfer(msg.sender, incentiveFee);
        unchecked {
            return e280Amount - incentiveFee;
        }
    }

    function _swapELMNT(address tokenOut, uint256 amountIn, uint256 minAmountOut, uint256 deadline) internal {
        IERC20(E280).safeIncreaseAllowance(UNISWAP_V2_ROUTER, amountIn);

        address[] memory path = new address[](2);
        path[0] = E280;
        path[1] = tokenOut;

        IUniswapV2Router02(UNISWAP_V2_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, minAmountOut, path, address(this), deadline
        );
    }

    function _swapDragonXforELMNT(uint256 amountIn, uint256 minAmountOut, uint256 deadline)
        internal
        returns (uint256)
    {
        IERC20(DRAGONX).safeIncreaseAllowance(UNISWAP_V2_ROUTER, amountIn);

        address[] memory path = new address[](2);
        path[0] = DRAGONX;
        path[1] = E280;

        uint256[] memory amounts = IUniswapV2Router02(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
            amountIn, minAmountOut, path, address(this), deadline
        );

        return amounts[1];
    }
}
