// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../Setup.t.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

/// @title ScaleBuyBurnFuzz Test Suite
/// @notice Fuzz tests for the ScaleBuyBurn contract
contract ScaleBuyBurnFuzz is Setup {
    /// @notice Fuzz test to ensure `buyAndBurn` correctly burns expected SCALE and HELIOS amounts
    /// @dev This test simulates `buyAndBurn` execution with random E280 and DragonX balances,
    ///      verifying that token swaps and burns adhere to expected constraints and state changes.
    /// @param e280AmountToFund Random amount of E280 to fund the contract, bounded between 1e18 and capPerSwapE280
    /// @param dragonXAmountToFund Random amount of DragonX to fund the contract, bounded at capPerSwapDragonX
    function testFuzzBuyAndBurn(
        uint256 e280AmountToFund,
        uint256 dragonXAmountToFund
    ) public {
        // Bound the funding amounts to practical limits
        e280AmountToFund = bound(e280AmountToFund, 1e18, capPerSwapE280);
        dragonXAmountToFund = bound(
            dragonXAmountToFund,
            capPerSwapDragonX,
            capPerSwapDragonX
        );

        // Fund the contract with the bounded amounts
        fundBuyBurnWithE280(e280AmountToFund);
        fundBuyBurnWithDragonX(dragonXAmountToFund);

        // Set deadline
        uint256 deadline = block.timestamp + 1 hours;

        // Capture initial states
        uint256 initialScaleTotalSupply = scale.totalSupply();
        uint256 initialHeliosTotalSupply = helios.totalSupply();
        uint256 initialUserE280Balance = e280.balanceOf(user);
        uint256 initialE280Balance = e280.balanceOf(address(buyBurnContract));

        // Execute buyAndBurn as the user
        vm.prank(user);
        buyBurnContract.buyAndBurn(0, 0, 0, deadline);

        // Calculate expected E280 swap amount and incentive fee
        uint256 expectedE280SwapAmount = initialE280Balance > capPerSwapE280
            ? capPerSwapE280
            : initialE280Balance;
        uint256 incentiveFee = (expectedE280SwapAmount *
            buyBurnContract.incentiveFeeBps()) / BPS_BASE;

        // Verify E280 swapped does not exceed the cap
        uint256 actualE280Swapped = e280.balanceOf(user) -
            initialUserE280Balance;
        assertLe(
            actualE280Swapped,
            capPerSwapE280,
            "E280 swapped exceeds capPerSwapE280"
        );

        // Ensure SCALE and HELIOS balances are zero after burning
        assertEq(
            scale.balanceOf(address(buyBurnContract)),
            0,
            "SCALE balance should be zero after burning"
        );
        assertEq(
            helios.balanceOf(address(buyBurnContract)),
            0,
            "HELIOS balance should be zero after burning"
        );

        // Check that lastBuyBurn is updated to the current block timestamp
        assertEq(buyBurnContract.lastBuyBurn(), block.timestamp);

        // Attempt to call buyAndBurn again within the cooldown period and expect it to revert
        vm.expectRevert(abi.encodeWithSelector(ScaleBuyBurn.Cooldown.selector));
        vm.prank(user);
        buyBurnContract.buyAndBurn(0, 0, 0, getDeadline());
    }

    /// @notice Fuzz test to ensure `buyAndBurn` reverts when minimum amount out parameters cannot be met.
    /// @dev Randomly generates `minScaleAmount` and `minHeliosAmount` greater than possible swap outputs.
    function testFuzzBuyAndBurnMinimumAmountOutRevert(
        uint256 e280AmountToFund,
        uint256 minScaleAmount,
        uint256 minHeliosAmount
    ) public {
        // Bound the funding amount
        e280AmountToFund = bound(
            e280AmountToFund,
            capPerSwapE280 / 2,
            capPerSwapE280
        );

        // Fund the contract
        fundBuyBurnWithE280(e280AmountToFund);

        // Bound minScaleAmount and minHeliosAmount to be greater than possible outputs
        // Assuming getQuote can be used to determine max possible output, here we set min amounts higher
        minScaleAmount = bound(
            minScaleAmount,
            (e280AmountToFund * 1000),
            type(uint256).max
        );
        minHeliosAmount = bound(
            minHeliosAmount,
            (e280AmountToFund * 1000),
            type(uint256).max
        );

        uint256 deadline = getDeadline();

        // Attempt to call buyAndBurn and expect a revert due to insufficient output amounts
        vm.prank(user);
        vm.expectRevert();
        buyBurnContract.buyAndBurn(
            minScaleAmount,
            minHeliosAmount,
            0,
            deadline
        );
    }

    /// @notice Fuzz test to ensure `buyAndBurn` cannot be called more than once per `buyBurnInterval`
    /// @dev This test verifies the cooldown mechanism by simulating varying time intervals between `buyAndBurn` calls.
    /// @param timePassed Random time interval to simulate passing between consecutive `buyAndBurn` calls, bounded between 0 and twice the `buyBurnInterval`
    function testFuzzBuyAndBurnCooldown(uint256 timePassed) public {
        // Bound timePassed to a reasonable range (0 - 2 * buyBurnInterval)
        timePassed = bound(
            timePassed,
            0,
            buyBurnContract.buyBurnInterval() * 2
        );

        // Fund the contract with E280 tokens
        uint256 amountToFund = capPerSwapE280;
        fundBuyBurnWithE280(amountToFund);

        uint256 minScaleAmount = 0;
        uint256 minHeliosAmount = 0;
        uint256 deadline = block.timestamp + 1 hours;

        // Call `buyAndBurn` for the first time
        vm.startPrank(user);

        buyBurnContract.buyAndBurn(
            minScaleAmount,
            minHeliosAmount,
            0,
            deadline
        );

        // Increase block timestamp
        vm.warp(block.timestamp + timePassed);

        // Attempt to call `buyAndBurn` again
        if (timePassed < buyBurnContract.buyBurnInterval()) {
            // Expect revert due to cooldown
            vm.expectRevert(
                abi.encodeWithSelector(ScaleBuyBurn.Cooldown.selector)
            );
            buyBurnContract.buyAndBurn(
                minScaleAmount,
                minHeliosAmount,
                0,
                deadline
            );
        } else {
            // Expect revert due to no E280 allocation
            vm.expectRevert(
                abi.encodeWithSelector(ScaleBuyBurn.NoAllocation.selector)
            );
            buyBurnContract.buyAndBurn(
                minScaleAmount,
                minHeliosAmount,
                0,
                deadline
            );
        }

        vm.stopPrank();
    }

    /// @notice Fuzz test to ensure swapped amounts do not exceed configured caps
    /// @dev This test checks that the amounts of E280 and DragonX swapped during `buyAndBurn` operations
    ///      do not surpass their respective maximum caps, even under varying input conditions.
    /// @param e280AmountToFund Random amount of E280 to fund, bounded between 0 and capPerSwapE280
    /// @param dragonXAmountToFund Random amount of DragonX to fund, bounded at capPerSwapDragonX
    function testFuzzSwapAmountsWithinCaps(
        uint256 e280AmountToFund,
        uint256 dragonXAmountToFund
    ) public {
        // Bound the amounts to [0, cap * 2] to test below, at, and above caps
        e280AmountToFund = bound(e280AmountToFund, 0, capPerSwapE280);
        dragonXAmountToFund = bound(
            dragonXAmountToFund,
            capPerSwapDragonX,
            capPerSwapDragonX
        );

        // Fund the contract
        fundBuyBurnWithE280(e280AmountToFund);
        fundBuyBurnWithDragonX(dragonXAmountToFund);

        uint256 minScaleAmount = 0;
        uint256 minHeliosAmount = 0;
        uint256 minE280Amount = 0;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 initialUserE280Balance = e280.balanceOf(user);

        // Capture initial balances
        uint256 initialE280Balance = e280.balanceOf(address(buyBurnContract));
        uint256 initialDragonXBalance = dragonx.balanceOf(
            address(buyBurnContract)
        );

        // Call `buyAndBurn` as a whitelisted user
        vm.prank(user);
        buyBurnContract.buyAndBurn(
            minScaleAmount,
            minHeliosAmount,
            minE280Amount,
            deadline
        );

        // Calculate expected E280 swap amount and incentive fee
        uint256 expectedE280SwapAmount = initialE280Balance > capPerSwapE280
            ? capPerSwapE280
            : initialE280Balance;
        uint256 incentiveFee = (expectedE280SwapAmount *
            buyBurnContract.incentiveFeeBps()) / BPS_BASE;

        uint256 dragonXBalanceAfter = dragonx.balanceOf(
            address(buyBurnContract)
        );

        // Verify E280 swapped does not exceed the cap
        uint256 actualE280Swapped = e280.balanceOf(user) -
            initialUserE280Balance;
        uint256 actualDragonXSwapped = initialDragonXBalance -
            dragonXBalanceAfter;

        assertLe(
            actualE280Swapped,
            capPerSwapE280,
            "E280 swapped exceeds capPerSwapE280"
        );

        assertLe(
            actualDragonXSwapped,
            capPerSwapDragonX,
            "DragonX swapped exceeds capPerSwapDragonX"
        );

        // Ensure SCALE and HELIOS balances are zero after burning
        assertEq(
            scale.balanceOf(address(buyBurnContract)),
            0,
            "SCALE balance should be zero after burning"
        );
        assertEq(
            helios.balanceOf(address(buyBurnContract)),
            0,
            "HELIOS balance should be zero after burning"
        );

        // Check that lastBuyBurn is updated to the current block timestamp
        assertEq(buyBurnContract.lastBuyBurn(), block.timestamp);

        // Attempt to call buyAndBurn again within the cooldown period and expect it to revert
        vm.expectRevert(abi.encodeWithSelector(ScaleBuyBurn.Cooldown.selector));
        vm.prank(user);
        buyBurnContract.buyAndBurn(0, 0, 0, getDeadline());
    }
}
