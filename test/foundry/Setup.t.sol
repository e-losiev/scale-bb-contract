// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Import Foundry's Test contract
import "forge-std/Test.sol";

// Import the ScaleBuyBurn contract and its dependencies
import "../../contracts/ScaleBuyBurn.sol";
import "../../contracts/interfaces/IERC20Burnable.sol";
import "../../contracts/interfaces/IHelios.sol";
import "../../contracts/lib/constants.sol";

// Import OpenZeppelin's IERC20 interface
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "forge-std/Console2.sol";

// Define the Setup contract
contract Setup is Test {
    // -------------------------- STATE VARIABLES -------------------------- //

    // Contracts
    ScaleBuyBurn public buyBurnContract;

    // ERC20 tokens
    IERC20 public e280 = IERC20(E280);
    IERC20 public dragonx = IERC20(DRAGONX);
    IERC20Burnable public scale = IERC20Burnable(SCALE);
    IHelios public helios = IHelios(HELIOS);

    // Addresses
    address public owner = vm.addr(1);
    address public user = vm.addr(2);
    address public user2 = vm.addr(3);
    address public user3 = vm.addr(4);

    // Constants from the contract
    uint256 public capPerSwapE280;
    uint256 public capPerSwapDragonX;
    uint32 public buyBurnInterval;
    uint16 public incentiveFeeBps;

    // Uniswap Router
    IUniswapV2Router02 public uniswapRouter =
        IUniswapV2Router02(UNISWAP_V2_ROUTER);

    // ----------------------------- SETUP FUNCTION ------------------------- //

    /// @notice This function sets up the initial state for the tests.
    function setUp() public virtual {
        // Deploy the ScaleBuyBurn contract
        buyBurnContract = new ScaleBuyBurn(owner);

        // Set the incentive fee to 30 bps (0.3%)
        vm.prank(owner);
        buyBurnContract.setIncentiveFee(30);

        // Retrieve constants from the deployed contract
        capPerSwapE280 = buyBurnContract.capPerSwapE280();
        capPerSwapDragonX = buyBurnContract.capPerSwapDragonX();
        buyBurnInterval = buyBurnContract.buyBurnInterval();
        incentiveFeeBps = buyBurnContract.incentiveFeeBps();

        // Whitelist the user address
        vm.prank(owner);
        address[] memory accounts = new address[](1);
        accounts[0] = user;
        buyBurnContract.setWhitelisted(accounts, true);

        // Approve E280 and DragonX tokens for the Uniswap Router
        // vm.prank(address(buyBurnContract));
        // e280.approve(address(uniswapRouter), type(uint256).max);

        // vm.prank(address(buyBurnContract));
        // dragonx.approve(address(uniswapRouter), type(uint256).max);

        // Label addresses for easier debugging
        vm.label(owner, "Owner");
        vm.label(user, "User");
        vm.label(user2, "User2");
        vm.label(user3, "User3");
        vm.label(address(buyBurnContract), "BuyBurnContract");

        vm.stopPrank();
    }

    // ------------------------- HELPER FUNCTIONS -------------------------- //

    /// @notice Funds the BuyBurnContract with E280 tokens.
    /// @param _amount The amount of E280 tokens to fund.
    function fundBuyBurnWithE280(uint256 _amount) public {
        deal(address(e280), address(buyBurnContract), _amount);
        console.log(
            "E280 Balance after funding:",
            e280.balanceOf(address(buyBurnContract))
        );
    }

    /// @notice Funds the BuyBurnContract with DRAGONX tokens.
    /// @param _amount The amount of DRAGONX tokens to fund.
    function fundBuyBurnWithDragonX(uint256 _amount) public {
        deal(address(dragonx), address(buyBurnContract), _amount);
        console.log(
            "DragonX Balance after funding:",
            dragonx.balanceOf(address(buyBurnContract))
        );
    }

    /// @notice Approves the BuyBurnContract to spend E280 tokens from the user.
    /// @param _amount The amount of E280 tokens to approve.
    function approveE280(uint256 _amount) public {
        vm.startPrank(user);
        e280.approve(address(buyBurnContract), _amount);
        vm.stopPrank();
    }

    /// @notice Approves the BuyBurnContract to spend DragonX tokens from the user.
    /// @param _amount The amount of DragonX tokens to approve.
    function approveDragonX(uint256 _amount) public {
        vm.startPrank(user);
        dragonx.approve(address(buyBurnContract), _amount);
        vm.stopPrank();
    }

    /// @notice Helper function to get the current timestamp plus a buffer.
    /// @return The deadline timestamp.
    function getDeadline() public view returns (uint256) {
        return block.timestamp + 1 hours;
    }

    /// @notice Calculates basis points.
    /// @param _amount The amount to calculate BPS on.
    /// @param _bps The basis points.
    /// @return The calculated BPS amount.
    function calculateBPS(
        uint256 _amount,
        uint256 _bps
    ) public pure returns (uint256) {
        return (_amount * _bps) / BPS_BASE;
    }

    /// @notice Applies slippage to a given amount (e.g., 1%).
    /// @param _amount The original amount.
    /// @return The amount after applying slippage.
    function applySlippage(uint256 _amount) public pure returns (uint256) {
        return (_amount * 99) / 100; // 1% slippage
    }

    /// @notice Fetches a quote from Uniswap V2.
    /// @param _amountIn The input amount.
    /// @param _tokenIn The input token address.
    /// @param _tokenOut The output token address.
    /// @return The output amount.
    function getQuote(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut
    ) public view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;

        uint256[] memory amounts = IUniswapV2Router02(UNISWAP_V2_ROUTER)
            .getAmountsOut(_amountIn, path);
        return amounts[1];
    }

    /// @notice Moves the block timestamp forward by a specified number of seconds.
    /// @param _seconds The number of seconds to move forward.
    function passTime(uint256 _seconds) public {
        vm.warp(block.timestamp + _seconds);
    }
}
