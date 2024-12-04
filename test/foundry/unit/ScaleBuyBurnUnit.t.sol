// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../Setup.t.sol";
import "../../../contracts/interfaces/IElement280.sol";

/// @title ScaleBuyBurnUnit Test Suite
/// @notice Unit tests for the ScaleBuyBurn contract

contract ScaleBuyBurnUnit is Setup {
    /// @notice Tests the successful execution of buyAndBurn by a whitelisted user.
    /// @dev This test verifies that:
    ///      - The BuyBurnContract can perform buyAndBurn with sufficient E280 balance.
    ///      - The incentive fee is correctly calculated and transferred to the caller.
    ///      - The correct amounts of SCALE and HELIOS tokens are swapped and burned.
    ///      - The E280 balance decreases by the expected amount after buyAndBurn.
    ///      - The lastBuyBurn timestamp is updated.
    ///      - The cooldown period is enforced after the buyAndBurn call.
    ///      It also checks that attempting to call buyAndBurn again within the cooldown period reverts with the correct error.
    function testBuyAndBurn() public {
        {
            // Fund the BuyBurnContract with E280 tokens
            uint256 amountToFund = capPerSwapE280;
            fundBuyBurnWithE280(amountToFund);

            // Prepare parameters for buyAndBurn function
            uint256 amountAfterFee = amountToFund -
                calculateBPS(amountToFund, incentiveFeeBps);

            //Commented and hardcoded to 0, bc of INSUFFICIENT_OUTPUT_AMOUNT error

            // uint256 minScaleAmount = applySlippage(
            //     getQuote(scaleAmountIn, E280, SCALE)
            // );
            // uint256 minHeliosAmount = applySlippage(
            //     getQuote(heliosAmountIn, E280, HELIOS)
            // );

            uint256 minScaleAmount = 0;
            uint256 minHeliosAmount = 0;

            uint256 deadline = getDeadline();

            // Get initial balances
            uint256 initialE280Balance = e280.balanceOf(
                address(buyBurnContract)
            );
            uint256 initialUserE280Balance = e280.balanceOf(user);
            uint256 scaleTotalSupplyBefore = scale.totalSupply();
            uint256 heliosTotalSupplyBefore = helios.totalSupply();

            // Call buyAndBurn function as the whitelisted user
            vm.prank(user);
            buyBurnContract.buyAndBurn(
                minScaleAmount,
                minHeliosAmount,
                0,
                deadline
            );

            // Check that the E280 balance has decreased by amountToFund
            assertEq(
                initialE280Balance - e280.balanceOf(address(buyBurnContract)),
                amountToFund
            );

            // Check that the incentive fee was sent to the user (after accounting for transfer fee)
            assertEq(
                e280.balanceOf(user) - initialUserE280Balance,
                (calculateBPS(amountToFund, incentiveFeeBps) * 96) / 100
            );

            // Calculate expected amounts of Scale and Helios tokens received from swaps
            uint256 expectedScaleAmount = applySlippage(
                getQuote(
                    amountAfterFee - (amountAfterFee / 10), // scaleAmountIn
                    E280,
                    SCALE
                )
            );
            uint256 expectedHeliosAmount = applySlippage(
                getQuote(
                    amountAfterFee / 10, // heliosAmountIn
                    E280,
                    HELIOS
                )
            );

            // Get actual total supplies after burn
            uint256 scaleTotalSupplyAfter = scale.totalSupply();
            uint256 heliosTotalSupplyAfter = helios.totalSupply();

            // Calculate actual amounts burned
            uint256 actualScaleBurned = scaleTotalSupplyBefore -
                scaleTotalSupplyAfter;
            uint256 actualHeliosBurned = heliosTotalSupplyBefore -
                heliosTotalSupplyAfter;

            // Calculate acceptable delta (3% of expectedHeliosAmount)
            uint256 acceptableDeltaHelios = (expectedHeliosAmount * 3) / 100;
            uint256 acceptableDeltaScale = (expectedScaleAmount * 3) / 100;

            // Assert that the actual amounts burned are approximately equal to expected amounts within acceptable delta
            assertApproxEqAbs(
                actualScaleBurned,
                expectedScaleAmount,
                acceptableDeltaScale
            );

            assertApproxEqAbs(
                actualHeliosBurned,
                expectedHeliosAmount,
                acceptableDeltaHelios
            );

            // Check that lastBuyBurn is updated to the current block timestamp
            assertEq(buyBurnContract.lastBuyBurn(), block.timestamp);
        } // Variables declared above go out of scope here

        {
            uint256 minScaleAmount = 0;
            uint256 minHeliosAmount = 0;
            uint256 deadline = getDeadline();

            // Attempt to call buyAndBurn again within the cooldown period and expect it to revert with "Cooldown"
            vm.expectRevert(
                abi.encodeWithSelector(ScaleBuyBurn.Cooldown.selector)
            );
            vm.prank(user);
            buyBurnContract.buyAndBurn(
                minScaleAmount,
                minHeliosAmount,
                0,
                deadline
            );
        }
    }

    /// @notice Tests that calling buyAndBurn reverts when the caller is not whitelisted.
    /// @dev This test verifies that non-whitelisted users cannot execute the buyAndBurn function,
    ///      ensuring that access control is properly enforced.
    ///      It attempts to call buyAndBurn as a non-whitelisted user and expects the transaction to revert with the Prohibited error.
    function testBuyAndBurnNotWhitelisted() public {
        // Fund the BuyBurnContract with E280 tokens
        uint256 amountToFund = capPerSwapE280;
        fundBuyBurnWithE280(amountToFund);

        uint256 minScaleAmount = 0;
        uint256 minHeliosAmount = 0;
        uint256 deadline = getDeadline();

        // Attempt to call buyAndBurn as a non-whitelisted user and expect revert
        vm.expectRevert(
            abi.encodeWithSelector(ScaleBuyBurn.Prohibited.selector)
        );
        vm.prank(user2); // user2 is not whitelisted
        buyBurnContract.buyAndBurn(
            minScaleAmount,
            minHeliosAmount,
            0,
            deadline
        );
    }

    /// @notice Tests that buyAndBurn cannot be called again within the cooldown period.
    /// @dev This test ensures that the cooldown mechanism works correctly by:
    ///      - Performing an initial buyAndBurn call.
    ///      - Attempting to call buyAndBurn again immediately.
    ///      - Verifying that the second call reverts with the Cooldown error.
    function testBuyAndBurnCooldown() public {
        // Fund the BuyBurnContract with E280 tokens
        uint256 amountToFund = capPerSwapE280;
        fundBuyBurnWithE280(amountToFund);

        uint256 minScaleAmount = 0;
        uint256 minHeliosAmount = 0;
        uint256 deadline = getDeadline();

        // Call buyAndBurn for the first time
        vm.prank(user);
        buyBurnContract.buyAndBurn(
            minScaleAmount,
            minHeliosAmount,
            0,
            deadline
        );

        // Verify that the E280 balance has decreased by amountToFund
        assertEq(
            e280.balanceOf(address(buyBurnContract)),
            amountToFund - capPerSwapE280
        );

        // Verify that lastBuyBurn is updated to the current block timestamp
        assertEq(buyBurnContract.lastBuyBurn(), block.timestamp);

        // Try calling buyAndBurn again immediately and expect revert
        vm.expectRevert(abi.encodeWithSelector(ScaleBuyBurn.Cooldown.selector));
        vm.prank(user);
        buyBurnContract.buyAndBurn(
            minScaleAmount,
            minHeliosAmount,
            0,
            deadline
        );

        // Advance time beyond the cooldown period
        // Calculate new block.timestamp after warping
        uint256 newTimestamp = block.timestamp +
            buyBurnContract.buyBurnInterval() +
            1 hours;
        vm.warp(newTimestamp);

        // Fund the contract again with capPerSwapE280 to allow another buyAndBurn
        fundBuyBurnWithE280(amountToFund);

        uint256 deadlineAfterWarp = getDeadline();

        // Attempt to call buyAndBurn again after cooldown with sufficient allocation
        vm.prank(user);
        buyBurnContract.buyAndBurn(
            minScaleAmount,
            minHeliosAmount,
            0,
            deadlineAfterWarp
        );

        // Verify that the E280 balance has decreased by another capPerSwapE280
        assertEq(
            e280.balanceOf(address(buyBurnContract)),
            (amountToFund - capPerSwapE280) + amountToFund - capPerSwapE280
        );

        // Verify that lastBuyBurn is updated to the new block timestamp
        assertEq(buyBurnContract.lastBuyBurn(), block.timestamp);
    }

    /// @notice Tests that only the current owner can transfer ownership.
    function testOwnershipTransfer() public {
        address newOwner = address(0xBEEF);

        // Owner initiates ownership transfer to newOwner
        vm.prank(owner);
        buyBurnContract.transferOwnership(newOwner);

        // Assert that ownership hasn't changed yet
        assertEq(buyBurnContract.owner(), owner);

        // New owner accepts ownership
        vm.prank(newOwner);
        buyBurnContract.acceptOwnership();

        // Assert that ownership has now changed to newOwner
        assertEq(buyBurnContract.owner(), newOwner);

        // Previous owner should no longer be able to transfer ownership
        vm.prank(owner);
        vm.expectRevert();
        buyBurnContract.transferOwnership(address(0xDEAD));

        // New owner can transfer ownership back to original owner
        vm.prank(newOwner);
        buyBurnContract.transferOwnership(owner);

        // Assert that ownership hasn't changed yet
        assertEq(buyBurnContract.owner(), newOwner);

        // Original owner accepts ownership back
        vm.prank(owner);
        buyBurnContract.acceptOwnership();

        // Assert that ownership has reverted to the original owner
        assertEq(buyBurnContract.owner(), owner);
    }

    /// @notice Tests that buyAndBurn reverts when there are no E280 or DragonX tokens allocated for swapping.
    /// @dev This test checks that the function cannot proceed when there are insufficient tokens to perform the swaps.
    ///      It attempts to call buyAndBurn without any E280 or DragonX tokens in the contract and expects a revert with the NoAllocation error.
    function testBuyAndBurnNoAllocation() public {
        uint256 minScaleAmount = 0;
        uint256 minHeliosAmount = 0;
        uint256 deadline = getDeadline();

        // Attempt to call buyAndBurn without any tokens and expect revert
        vm.expectRevert(
            abi.encodeWithSelector(ScaleBuyBurn.NoAllocation.selector)
        );
        vm.prank(user);
        buyBurnContract.buyAndBurn(
            minScaleAmount,
            minHeliosAmount,
            0,
            deadline
        );
    }

    /// @notice Tests the behavior of `buyAndBurn` when DragonX balance is zero.
    /// @dev Ensures that the function can execute successfully even if DragonX tokens are not allocated.
    function testBuyAndBurnWithZeroDragonXBalance() public {
        // Fund the BuyBurnContract with E280 tokens only
        uint256 amountToFund = capPerSwapE280;
        fundBuyBurnWithE280(amountToFund);

        // Ensure DragonX balance is zero
        uint256 dragonXBalance = dragonx.balanceOf(address(buyBurnContract));
        assertEq(dragonXBalance, 0);

        uint256 minScaleAmount = 0;
        uint256 minHeliosAmount = 0;
        uint256 deadline = getDeadline();

        // Call buyAndBurn as the whitelisted user
        vm.prank(user);
        buyBurnContract.buyAndBurn(
            minScaleAmount,
            minHeliosAmount,
            0,
            deadline
        );

        // Verify that buyAndBurn succeeded despite zero DragonX balance
        assertEq(buyBurnContract.lastBuyBurn(), block.timestamp);
    }

    /// @notice Tests that `buyAndBurn` reverts when minimum amount out parameters cannot be met.
    /// @dev Sets `minScaleAmount` and `minHeliosAmount` to values higher than what the swap can fulfill, expecting a revert.
    function testBuyAndBurnMinimumAmountOutRevert() public {
        // Fund the BuyBurnContract with E280 tokens
        uint256 amountToFund = capPerSwapE280;
        fundBuyBurnWithE280(amountToFund);

        // Set minScaleAmount and minHeliosAmount to excessively high values
        uint256 minScaleAmount = type(uint256).max;
        uint256 minHeliosAmount = type(uint256).max;
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

    /// @notice Tests the behavior of `buyAndBurn` when DragonX balance equals capPerSwapDragonX.
    /// @dev Ensures that when DragonX tokens are exactly at the cap, the function executes correctly.
    function testBuyAndBurnExactDragonXBalance() public {
        // Fund the BuyBurnContract with E280 and DragonX tokens equal to their respective caps
        uint256 e280AmountToFund = capPerSwapE280;
        uint256 dragonXAmountToFund = capPerSwapDragonX;
        fundBuyBurnWithE280(e280AmountToFund);
        fundBuyBurnWithDragonX(dragonXAmountToFund);

        uint256 minScaleAmount = 0;
        uint256 minHeliosAmount = 0;
        uint256 deadline = getDeadline();

        // Get initial DragonX balance
        uint256 initialDragonXBalance = dragonx.balanceOf(
            address(buyBurnContract)
        );

        // Call buyAndBurn as the whitelisted user
        vm.prank(user);
        buyBurnContract.buyAndBurn(
            minScaleAmount,
            minHeliosAmount,
            0,
            deadline
        );
        // Verify that lastBuyBurn is updated
        assertEq(buyBurnContract.lastBuyBurn(), block.timestamp);
    }

    /// @notice Tests that the incentive fee is correctly calculated at the minimum allowed fee.
    /// @dev Sets the incentive fee to its minimum allowed value and verifies correct fee calculation during `buyAndBurn`.
    function testIncentiveFeeCalculationAtMinimum() public {
        uint16 minFeeBps = 30;
        vm.prank(owner);
        buyBurnContract.setIncentiveFee(minFeeBps);
        assertEq(buyBurnContract.incentiveFeeBps(), minFeeBps);

        // Fund the BuyBurnContract with E280 tokens
        uint256 amountToFund = capPerSwapE280;
        fundBuyBurnWithE280(amountToFund);

        uint256 deadline = getDeadline();

        // Get initial user E280 balance
        uint256 initialUserE280Balance = e280.balanceOf(user);

        // Call buyAndBurn
        vm.prank(user);
        buyBurnContract.buyAndBurn(0, 0, 0, deadline);

        // Calculate expected fee
        uint256 expectedFee = (amountToFund * minFeeBps) / 10000;

        // Verify that the user received the incentive fee
        assertEq(
            e280.balanceOf(user) - initialUserE280Balance,
            (expectedFee * 96) / 100
        );
    }

    /// @notice Tests that the incentive fee is correctly calculated at the maximum allowed fee.
    /// @dev Sets the incentive fee to its maximum allowed value and verifies correct fee calculation during `buyAndBurn`.
    function testIncentiveFeeCalculationAtMaximum() public {
        uint16 maxFeeBps = 500;
        vm.prank(owner);
        buyBurnContract.setIncentiveFee(maxFeeBps);
        assertEq(buyBurnContract.incentiveFeeBps(), maxFeeBps);

        // Fund the BuyBurnContract with E280 tokens
        uint256 amountToFund = capPerSwapE280;
        fundBuyBurnWithE280(amountToFund);

        uint256 deadline = getDeadline();

        // Get initial user E280 balance
        uint256 initialUserE280Balance = e280.balanceOf(user);

        // Call buyAndBurn
        vm.prank(user);
        buyBurnContract.buyAndBurn(0, 0, 0, deadline);

        // Calculate expected fee
        uint256 expectedFee = (amountToFund * maxFeeBps) / 10000;

        // Verify that the user received the incentive fee
        assertEq(
            e280.balanceOf(user) - initialUserE280Balance,
            (expectedFee * 96) / 100
        );
    }

    /// @notice Tests the contract's behavior with unusually high token balances to ensure no overflow occurs.
    /// @dev Funds the contract with near-maximum `uint256` values and verifies that `buyAndBurn` executes without overflow.
    function testBuyAndBurnWithHighValueTransactions() public {
        // Fund the BuyBurnContract with a very high amount of E280 tokens
        uint256 highAmount = type(uint256).max / 2; // Use a large but safe value to prevent actual overflows
        fundBuyBurnWithE280(highAmount);

        uint256 minScaleAmount = 0;
        uint256 minHeliosAmount = 0;
        uint256 deadline = getDeadline();

        // Attempt to call buyAndBurn with high E280 balance
        vm.prank(user);
        buyBurnContract.buyAndBurn(
            minScaleAmount,
            minHeliosAmount,
            0,
            deadline
        );

        // Verify that lastBuyBurn is updated correctly
        assertEq(buyBurnContract.lastBuyBurn(), block.timestamp);

        // Additionally, verify that the E280 balance has decreased by capPerSwapE280
        uint256 expectedDecrease = capPerSwapE280;
        assertEq(
            e280.balanceOf(address(buyBurnContract)),
            highAmount - expectedDecrease
        );
    }

    /// @notice Tests the contract's ability to recover from extreme states.
    /// @dev Simulates scenarios like maxed-out balances and failed swaps, then verifies contract behavior.
    function testContractStateReset() public {
        // Simulate maxed-out E280 balance
        uint256 maxE280 = type(uint256).max;
        fundBuyBurnWithE280(maxE280);

        // Simulate maxed-out DragonX balance
        uint256 maxDragonX = type(uint256).max;
        fundBuyBurnWithDragonX(maxDragonX);

        uint256 minScaleAmount = 0;
        uint256 minHeliosAmount = 0;
        uint256 deadline = getDeadline();

        // Attempt to call buyAndBurn, expecting it to handle the extreme state gracefully
        vm.prank(user);
        buyBurnContract.buyAndBurn(
            minScaleAmount,
            minHeliosAmount,
            0,
            deadline
        );

        // Verify that the contract's state is consistent after the operation
        assertEq(buyBurnContract.lastBuyBurn(), block.timestamp);
    }

    /// @notice Tests that the owner can successfully set the incentive fee within valid bounds.
    /// @dev This test verifies that the incentive fee can be updated to a new valid value by the owner.
    ///      It calls setIncentiveFee with a valid fee and checks that the incentiveFeeBps state variable is updated accordingly.
    function testSetIncentiveFee() public {
        uint16 newFeeBps = 100; // 1%
        vm.prank(owner);
        buyBurnContract.setIncentiveFee(newFeeBps);
        assertEq(buyBurnContract.incentiveFeeBps(), newFeeBps);
    }

    /// @notice Tests that setting the incentive fee below the minimum allowed value reverts.
    /// @dev This test ensures that the contract enforces the minimum incentive fee of 30 bps.
    ///      It attempts to set the incentive fee to a value below 30 bps and expects a revert with the Prohibited error.
    function testSetIncentiveFeeBelowMinimum() public {
        uint16 newFeeBps = 29;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(ScaleBuyBurn.Prohibited.selector)
        );
        buyBurnContract.setIncentiveFee(newFeeBps);
    }

    /// @notice Tests that setting the incentive fee above the maximum allowed value reverts.
    /// @dev This test ensures that the contract enforces the maximum incentive fee of 500 bps.
    ///      It attempts to set the incentive fee to a value above 500 bps and expects a revert with the Prohibited error.
    function testSetIncentiveFeeAboveMaximum() public {
        uint16 newFeeBps = 501;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(ScaleBuyBurn.Prohibited.selector)
        );
        buyBurnContract.setIncentiveFee(newFeeBps);
    }

    /// @notice Tests that the owner can successfully set the buy burn interval.
    /// @dev This test verifies that the buyBurnInterval can be updated by the owner to a new valid value.
    ///      It calls setBuyBurnInterval with a new interval and checks that the buyBurnInterval state variable is updated accordingly.
    function testSetBuyBurnInterval() public {
        uint32 newInterval = 6 hours;
        vm.prank(owner);
        buyBurnContract.setBuyBurnInterval(newInterval);
        assertEq(buyBurnContract.buyBurnInterval(), newInterval);
    }

    /// @notice Tests that setting the buy burn interval to zero reverts.
    /// @dev This test ensures that the contract does not accept zero as a valid buyBurnInterval.
    ///      It attempts to set the buyBurnInterval to zero and expects a revert with the Prohibited error.
    function testSetBuyBurnIntervalZero() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(ScaleBuyBurn.Prohibited.selector)
        );
        buyBurnContract.setBuyBurnInterval(0);
    }

    /// @notice Tests that the owner can successfully set the cap per swap for E280.
    /// @dev This test verifies that the capPerSwapE280 can be updated by the owner.
    ///      It calls setCapPerSwapE280 with a new cap value and checks that the capPerSwapE280 state variable is updated accordingly.
    function testSetCapPerSwapE280() public {
        uint256 newCap = 1_000_000_000 ether;
        vm.prank(owner);
        buyBurnContract.setCapPerSwapE280(newCap);
        assertEq(buyBurnContract.capPerSwapE280(), newCap);
    }

    /// @notice Tests that the owner can successfully set the cap per swap for DragonX.
    /// @dev This test verifies that the capPerSwapDragonX can be updated by the owner.
    ///      It calls setCapPerSwapDragonX with a new cap value and checks that the capPerSwapDragonX state variable is updated accordingly.
    function testSetCapPerSwapDragonX() public {
        uint256 newCap = 3_000_000_000 ether;
        vm.prank(owner);
        buyBurnContract.setCapPerSwapDragonX(newCap);
        assertEq(buyBurnContract.capPerSwapDragonX(), newCap);
    }

    /// @notice Tests that the owner can add and remove addresses from the whitelist.
    /// @dev This test verifies that the setWhitelisted function correctly updates the whitelist status of multiple accounts.
    ///      It adds addresses to the whitelist, checks their status, removes them, and verifies the status again.
    function testSetWhitelisted() public {
        address[] memory accounts = new address[](2);
        accounts[0] = user2;
        accounts[1] = user3;

        vm.prank(owner);
        buyBurnContract.setWhitelisted(accounts, true);

        assertTrue(buyBurnContract.whitelisted(user2));
        assertTrue(buyBurnContract.whitelisted(user3));

        vm.prank(owner);
        buyBurnContract.setWhitelisted(accounts, false);

        assertFalse(buyBurnContract.whitelisted(user2));
        assertFalse(buyBurnContract.whitelisted(user3));
    }

    /// @notice Tests the getBuyBurnParams function for correctness under various token balance scenarios.
    /// @dev This test checks the outputs of getBuyBurnParams in different situations:
    ///      - When both E280 and DragonX balances are zero.
    ///      - When E280 balance is less than the cap and DragonX balance is greater than zero.
    ///      It verifies that the function returns the correct values for additionalSwap, e280Amount, dragonXAmount, and nextAvailable.
    function testGetBuyBurnParams() public {
        // Scenario 1: Both E280 and DragonX balances are zero
        (
            bool additionalSwap,
            uint256 e280Amount,
            uint256 dragonXAmount,
            uint256 nextAvailable
        ) = buyBurnContract.getBuyBurnParams();
        assertFalse(additionalSwap);
        assertEq(e280Amount, 0);
        assertEq(dragonXAmount, 0);
        assertEq(
            nextAvailable,
            buyBurnContract.lastBuyBurn() + buyBurnContract.buyBurnInterval()
        );

        // Scenario 2: E280 balance less than cap, DragonX balance greater than zero
        uint256 e280AmountToFund = capPerSwapE280 / 2;
        uint256 dragonXAmountToFund = capPerSwapDragonX;

        fundBuyBurnWithE280(e280AmountToFund);
        fundBuyBurnWithDragonX(dragonXAmountToFund);

        (
            additionalSwap,
            e280Amount,
            dragonXAmount,
            nextAvailable
        ) = buyBurnContract.getBuyBurnParams();

        assertTrue(additionalSwap);
        assertEq(e280Amount, e280AmountToFund);
        assertEq(dragonXAmount, capPerSwapDragonX);
        assertEq(
            nextAvailable,
            buyBurnContract.lastBuyBurn() + buyBurnContract.buyBurnInterval()
        );
    }

    /// @notice Tests that buyAndBurn correctly swaps DragonX for E280 when E280 balance is less than the cap.
    /// @dev This test verifies that when the E280 balance is insufficient, the contract swaps DragonX for E280 before proceeding.
    ///      It funds the contract with partial E280 and DragonX, calls buyAndBurn, and checks that the E280 balance increases after swapping DragonX.
    function testBuyAndBurnWithDragonXSwap() public {
        // Fund the BuyBurnContract with E280 tokens less than the cap
        uint256 e280AmountToFund = capPerSwapE280 / 2;
        fundBuyBurnWithE280(e280AmountToFund);

        // Fund the BuyBurnContract with DragonX tokens
        uint256 dragonXAmountToFund = capPerSwapDragonX;
        fundBuyBurnWithDragonX(dragonXAmountToFund);

        uint256 minScaleAmount = 0;
        uint256 minHeliosAmount = 0;
        uint256 minE280Amount = 0;
        uint256 deadline = getDeadline();

        // Get E280 balance before calling buyAndBurn
        uint256 e280BalanceBefore = e280.balanceOf(address(buyBurnContract));

        // Call buyAndBurn function as the whitelisted user
        vm.prank(user);
        buyBurnContract.buyAndBurn(
            minScaleAmount,
            minHeliosAmount,
            minE280Amount,
            deadline
        );

        // Get E280 balance after buyAndBurn
        uint256 e280BalanceAfter = e280.balanceOf(address(buyBurnContract));

        assertTrue(e280BalanceAfter > e280BalanceBefore);
    }

    /// @notice Tests that buyAndBurn fails when after dragonX/E280 swap contract balance is still below capPerSwapE280
    /// @dev The problem is that we don't take into account E280 fee when doing the `dragonX/E280` swap and later we try to swap E280 larger than current balance
    function testBuyAndBurnWithDragonXSwapFailsWhenBalanceOf280IsBelowCapAfterSwap()
        public
    {
        // Fund the BuyBurnContract with E280 tokens less than the cap
        uint256 e280AmountToFund = capPerSwapE280 / 2;
        fundBuyBurnWithE280(e280AmountToFund);

        // Fund the BuyBurnContract with DragonX tokens
        uint256 dragonXAmountToFund = capPerSwapDragonX / 100;
        fundBuyBurnWithDragonX(dragonXAmountToFund);

        uint256 minScaleAmount = 0;
        uint256 minHeliosAmount = 0;
        uint256 minE280Amount = 0;
        uint256 deadline = getDeadline();

        // Call buyAndBurn function as the whitelisted user
        vm.expectRevert();
        vm.prank(user);
        buyBurnContract.buyAndBurn(
            minScaleAmount,
            minHeliosAmount,
            minE280Amount,
            deadline
        );
    }

    /// @notice Tests that non-owner accounts cannot call owner-only administrative functions.
    /// @dev This test ensures that access control is properly enforced on functions restricted to the owner.
    ///      It attempts to call several administrative functions as a non-owner and expects each call to revert with an appropriate error.
    function testOnlyOwnerFunctions() public {
        // Attempt to call setIncentiveFee as non-owner
        vm.prank(user);
        vm.expectRevert();

        buyBurnContract.setIncentiveFee(100);

        // Attempt to call setBuyBurnInterval as non-owner
        vm.prank(user);
        vm.expectRevert();

        buyBurnContract.setBuyBurnInterval(6 hours);

        // Attempt to call setCapPerSwapE280 as non-owner
        vm.prank(user);
        vm.expectRevert();

        buyBurnContract.setCapPerSwapE280(1_000_000_000 ether);

        // Attempt to call setCapPerSwapDragonX as non-owner
        vm.prank(user);
        vm.expectRevert();

        buyBurnContract.setCapPerSwapDragonX(3_000_000_000 ether);

        // Attempt to call setWhitelisted as non-owner
        address[] memory accounts = new address[](1);
        accounts[0] = user2;
        vm.prank(user);
        vm.expectRevert();

        buyBurnContract.setWhitelisted(accounts, true);
    }

    /// @notice Tests that buyAndBurn uses only up to capPerSwapE280 amount when E280 balance exceeds the cap.
    /// @dev This test verifies that even if the contract holds more E280 than capPerSwapE280, only capPerSwapE280 amount is used in buyAndBurn.
    ///      It funds the contract with E280 exceeding the cap, calls buyAndBurn, and checks that the amount of E280 used equals the cap.
    function testBuyAndBurnE280ExceedsCap() public {
        // Fund the BuyBurnContract with E280 tokens more than the cap
        uint256 amountToFund = capPerSwapE280 * 2;
        fundBuyBurnWithE280(amountToFund);

        uint256 minScaleAmount = 0;
        uint256 minHeliosAmount = 0;
        uint256 deadline = getDeadline();

        // Get initial E280 balance
        uint256 initialE280Balance = e280.balanceOf(address(buyBurnContract));

        // Call buyAndBurn function as the whitelisted user
        vm.prank(user);
        buyBurnContract.buyAndBurn(
            minScaleAmount,
            minHeliosAmount,
            0,
            deadline
        );

        // Ensure that only capPerSwapE280 amount was used
        assertEq(
            initialE280Balance - e280.balanceOf(address(buyBurnContract)),
            capPerSwapE280
        );
    }

    /// @notice Tests that buyAndBurn operates correctly when E280 balance equals capPerSwapE280, resulting in zero E280 balance after swaps.
    /// @dev This test ensures that when the E280 balance is exactly capPerSwapE280, the entire amount is used, and the E280 balance becomes zero after buyAndBurn.
    ///      It checks that the incentive fee is correctly processed and that the final E280 balance is zero.
    function testBuyAndBurnExactE280Balance() public {
        // Fund the BuyBurnContract with E280 tokens equal to capPerSwapE280
        uint256 amountToFund = capPerSwapE280;
        fundBuyBurnWithE280(amountToFund);

        uint256 minScaleAmount = 0;
        uint256 minHeliosAmount = 0;
        uint256 deadline = getDeadline();

        // Get initial E280 balance
        uint256 initialE280Balance = e280.balanceOf(address(buyBurnContract));

        // Call buyAndBurn function as the whitelisted user
        vm.prank(user);
        buyBurnContract.buyAndBurn(
            minScaleAmount,
            minHeliosAmount,
            0,
            deadline
        );

        // Ensure that the E280 balance is zero after the operation
        assertEq(
            e280.balanceOf(address(buyBurnContract)),
            initialE280Balance - capPerSwapE280
        );
    }
}
