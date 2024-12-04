// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../Setup.t.sol";
import "../../../contracts/ScaleBuyBurn.sol";
import "../../../contracts/interfaces/IERC20Burnable.sol";
import "../../../contracts/interfaces/IHelios.sol";

/// @title ScaleBuyBurnInvariant Test Suite
/// @notice Invariant tests for the ScaleBuyBurn contract
contract ScaleBuyBurnInvariant is Setup {
    /// @notice Helper function to perform `buyAndBurn` with default parameters
    /// @dev This internal function funds the contract with the necessary E280 tokens and executes `buyAndBurn` as a whitelisted user.
    function performBuyAndBurn() internal {
        uint256 minScaleAmount = 0;
        uint256 minHeliosAmount = 0;
        uint256 minE280Amount = 0;
        uint256 deadline = block.timestamp + 1 hours;

        // Ensure the contract has enough E280 to perform the swap
        uint256 amountToFund = capPerSwapE280;
        fundBuyBurnWithE280(amountToFund);

        // Execute buyAndBurn as a whitelisted user
        vm.prank(user);
        buyBurnContract.buyAndBurn(
            minScaleAmount,
            minHeliosAmount,
            minE280Amount,
            deadline
        );
    }

    /// @notice Invariant: Only whitelisted addresses can execute `buyAndBurn`
    /// @dev Attempts to call `buyAndBurn` from a variety of non-whitelisted addresses, ensuring all fail.
    function invariant_onlyWhitelistedCanExecuteBuyAndBurn() external {
        // Define multiple non-whitelisted addresses
        address[] memory nonWhitelistedUsers = new address[](3);
        nonWhitelistedUsers[0] = user2;
        nonWhitelistedUsers[1] = user3;
        nonWhitelistedUsers[2] = address(0xDEAD);

        for (uint256 i = 0; i < nonWhitelistedUsers.length; i++) {
            vm.prank(nonWhitelistedUsers[i]);
            vm.expectRevert(
                abi.encodeWithSelector(ScaleBuyBurn.Prohibited.selector)
            );
            buyBurnContract.buyAndBurn(0, 0, 0, getDeadline());
        }
    }

    /// @notice Invariant: `buyAndBurn` can only be called once every `buyBurnInterval` seconds
    /// @dev This invariant verifies that the cooldown period between consecutive `buyAndBurn` calls is strictly enforced, preventing rapid successive executions.
    function invariant_buyBurnIntervalCooldown() external {
        // Perform the first buyAndBurn
        performBuyAndBurn();

        // Attempt to call buyAndBurn again immediately
        vm.prank(user);
        uint256 minScaleAmount = 0;
        uint256 minHeliosAmount = 0;
        uint256 minE280Amount = 0;
        uint256 deadline = block.timestamp + 1 hours;

        vm.expectRevert(abi.encodeWithSelector(ScaleBuyBurn.Cooldown.selector));
        buyBurnContract.buyAndBurn(
            minScaleAmount,
            minHeliosAmount,
            minE280Amount,
            deadline
        );
    }

    /// @notice Invariant: Always swap DragonX ≤ capPerSwapDragonX per `buyAndBurn`
    /// @dev This invariant ensures that the amount of DragonX tokens swapped during each `buyAndBurn` execution does not exceed the predefined maximum cap.
    function invariant_swapDragonXWithinCap() external {
        // Perform buyAndBurn which may involve swapping DragonX
        performBuyAndBurn();

        // Check that DragonX swapped does not exceed capPerSwapDragonX
        uint256 dragonxBalance = dragonx.balanceOf(address(buyBurnContract));
        assertLe(dragonxBalance, capPerSwapDragonX);
    }

    /// @notice Invariant: Always swap E280 ≤ capPerSwapE280 per `buyAndBurn`
    /// @dev This invariant ensures that the amount of E280 tokens swapped during each `buyAndBurn` execution does not exceed the predefined maximum cap.
    function invariant_swapE280WithinCap() external {
        // Perform buyAndBurn which involves swapping E280
        performBuyAndBurn();

        // Check that E280 swapped does not exceed capPerSwapE280
        uint256 e280Balance = e280.balanceOf(address(buyBurnContract));
        assertLe(e280Balance, capPerSwapE280);
    }

    /// @notice Invariant: Helios & Scale balances should always be 0 after calling `buyAndBurn`
    /// @dev This invariant ensures that post `buyAndBurn` execution, the contract holds no residual Helios or Scale tokens, confirming successful burns.
    function invariant_heliosAndScaleBalancesZeroAfterBuyAndBurn() external {
        // Perform buyAndBurn
        performBuyAndBurn();

        // Assert that Helios and Scale balances are zero
        assertEq(
            helios.balanceOf(address(buyBurnContract)),
            0,
            "Helios balance is not zero"
        );
        assertEq(
            scale.balanceOf(address(buyBurnContract)),
            0,
            "Scale balance is not zero"
        );
    }

    /// @notice Invariant: `buyAndBurn` can only be called once every `buyBurnInterval` seconds
    /// @dev Performs multiple `buyAndBurn` calls with varying time intervals to ensure cooldown is enforced.
    function invariant_buyBurnIntervalCooldownMultipleCalls() external {
        // Fund the contract
        performBuyAndBurn();

        // Define multiple time intervals to test
        uint256[] memory timeIntervals = new uint256[](3);

        timeIntervals[0] = buyBurnContract.buyBurnInterval() / 2; // Within cooldown
        timeIntervals[1] = buyBurnContract.buyBurnInterval(); // Exactly cooldown
        timeIntervals[2] = buyBurnContract.buyBurnInterval() * 2; // Beyond cooldown

        for (uint256 i = 0; i < timeIntervals.length; i++) {
            vm.warp(block.timestamp + timeIntervals[i]);

            if (timeIntervals[i] < buyBurnContract.buyBurnInterval()) {
                // Expect cooldown revert
                vm.prank(user);
                vm.expectRevert(
                    abi.encodeWithSelector(ScaleBuyBurn.Cooldown.selector)
                );
                buyBurnContract.buyAndBurn(0, 0, 0, getDeadline());
            } else {
                // Expect NoAllocation revert if not funded
                vm.prank(user);
                vm.expectRevert(
                    abi.encodeWithSelector(ScaleBuyBurn.NoAllocation.selector)
                );
                buyBurnContract.buyAndBurn(0, 0, 0, getDeadline());
            }
        }
    }
}
