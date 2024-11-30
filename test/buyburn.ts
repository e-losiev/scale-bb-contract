import { time, loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";

import { getQuoteV2, passHours, calculateBPS, getDeadline, applySlippage, calculatePercentage } from "../config/utils";

import {
    buyBurnFullFundedWithBoth,
    buyBurnFundedDragonXFixture,
    buyBurnFundedE280Fixture,
    buyBurnFundedWithBoth,
    deployFixture,
} from "../config/fixtures";

describe("SCALE BUY BURN", function () {
    describe("Deployment && Errors", function () {
        it("Should set correct owner", async function () {
            const { buyburn, owner } = await loadFixture(deployFixture);
            expect(await buyburn.owner()).to.eq(owner);
        });
        it("Should revert with no balance", async function () {
            const { buyburn, user } = await loadFixture(deployFixture);
            await expect(buyburn.connect(user).buyAndBurn(0, 0, 0, 0)).to.be.revertedWithCustomError(buyburn, "NoAllocation");
        });
        it("Should revert non-whitelisted", async function () {
            const { buyburn, user2 } = await loadFixture(buyBurnFundedE280Fixture);
            await expect(buyburn.connect(user2).buyAndBurn(0, 0, 0, 0)).to.be.revertedWithCustomError(buyburn, "Prohibited");
        });
    });
    describe("BuyBurn", function () {
        it("Should perform a buy burn using e280 only", async function () {
            const { buyburn, user, e280, scale, helios, capPerSwapE280, buyBurnInterval } = await loadFixture(buyBurnFundedE280Fixture);
            const [additionalSwap, nextE280Swap, nextDragonXSwap, nextBuyBurn] = await buyburn.getBuyBurnParams();
            expect(additionalSwap).to.eq(false);
            expect(nextE280Swap).to.eq(capPerSwapE280);
            expect(nextDragonXSwap).to.eq(0);
            expect(nextBuyBurn).to.eq(buyBurnInterval);

            // const totalScaleBurnedToDate = await buyburn.totalScaleBurned();
            // const totalHeliosBurnedToDate = await buyburn.totalHeliosBurned();
            // const totalE280UsedToDate = await buyburn.totalE280Used();

            const incentiveFee = calculateBPS(nextE280Swap, 30);
            const allocationAfterIncentive = nextE280Swap - incentiveFee;

            const heliosAmountIn = allocationAfterIncentive / 10n;
            const scaleAmountIn = allocationAfterIncentive - heliosAmountIn;
            const heliosAmountOut = await getQuoteV2(e280.target, helios.target, heliosAmountIn);
            const scaleAmountOut = await getQuoteV2(e280.target, scale.target, scaleAmountIn);

            const scaleAfterTax = scaleAmountOut - calculateBPS(scaleAmountOut, 700);
            const minScaleAmount = applySlippage(scaleAfterTax);
            const minHeliosAmount = applySlippage(heliosAmountOut);
            const deadline = await getDeadline();
            await expect(buyburn.connect(user).buyAndBurn(minScaleAmount, minHeliosAmount, 0, deadline)).to.changeTokenBalances(
                e280,
                [buyburn, user],
                [-nextE280Swap, incentiveFee]
            );
            const timestamp = await time.latest();

            // expect(await buyburn.totalE280Used()).to.eq(totalE280UsedToDate + nextE280Swap);
            expect(await buyburn.lastBuyBurn()).to.eq(timestamp);
            // expect(await buyburn.totalScaleBurned()).to.approximately(totalScaleBurnedToDate + scaleAfterTax, calculatePercentage(scaleAfterTax, 1));
            // expect(await buyburn.totalHeliosBurned()).to.eq(totalHeliosBurnedToDate + heliosAmountOut);
            await expect(buyburn.connect(user).buyAndBurn(0, 0, 0, 0)).to.be.revertedWithCustomError(buyburn, "Cooldown");
        });
        it("Should perform a buy burn using dragonx only - dragonx check", async function () {
            const { buyburn, user, e280, helios, dragonx, scale, capPerSwapE280, capPerSwapDragonX, buyBurnInterval } = await loadFixture(
                buyBurnFundedDragonXFixture
            );
            const [additionalSwap, nextE280Swap, nextDragonXSwap, nextBuyBurn] = await buyburn.getBuyBurnParams();
            expect(additionalSwap).to.eq(true);
            expect(nextE280Swap).to.eq(0);
            expect(nextDragonXSwap).to.eq(capPerSwapDragonX);
            expect(nextBuyBurn).to.eq(buyBurnInterval);

            // const totalScaleBurnedToDate = await buyburn.totalScaleBurned();
            // const totalHeliosBurnedToDate = await buyburn.totalHeliosBurned();
            // const totalE280UsedToDate = await buyburn.totalE280Used();

            const e280AmountOut = await getQuoteV2(dragonx.target, e280.target, nextDragonXSwap);
            expect(e280AmountOut).to.be.greaterThan(capPerSwapE280);

            const incentiveFee = calculateBPS(capPerSwapE280, 30);
            const allocationAfterIncentive = capPerSwapE280 - incentiveFee;

            const heliosAmountIn = allocationAfterIncentive / 10n;
            const scaleAmountIn = allocationAfterIncentive - heliosAmountIn;
            const heliosAmountOut = await getQuoteV2(e280.target, helios.target, heliosAmountIn);
            const scaleAmountOut = await getQuoteV2(e280.target, scale.target, scaleAmountIn);

            const scaleAfterTax = scaleAmountOut - calculateBPS(scaleAmountOut, 700);
            const minScaleAmount = applySlippage(scaleAfterTax);
            const minHeliosAmount = applySlippage(heliosAmountOut);
            const deadline = await getDeadline();
            await expect(buyburn.connect(user).buyAndBurn(minScaleAmount, minHeliosAmount, 0, deadline)).to.changeTokenBalances(
                dragonx,
                [buyburn, user],
                [-capPerSwapDragonX, 0]
            );
            const timestamp = await time.latest();

            // expect(await buyburn.totalE280Used()).to.eq(totalE280UsedToDate + capPerSwapE280);
            expect(await buyburn.lastBuyBurn()).to.eq(timestamp);
            // expect(await buyburn.totalScaleBurned()).to.approximately(totalScaleBurnedToDate + scaleAfterTax, calculatePercentage(scaleAfterTax, 1));
            // expect(await buyburn.totalHeliosBurned()).to.eq(totalHeliosBurnedToDate + heliosAmountOut);
            await expect(buyburn.connect(user).buyAndBurn(0, 0, 0, 0)).to.be.revertedWithCustomError(buyburn, "Cooldown");
        });
        it("Should perform a buy burn using dragonx only - e280 check", async function () {
            const { buyburn, user, e280, helios, dragonx, scale, capPerSwapE280, capPerSwapDragonX, buyBurnInterval } = await loadFixture(
                buyBurnFundedDragonXFixture
            );
            const [additionalSwap, nextE280Swap, nextDragonXSwap, nextBuyBurn] = await buyburn.getBuyBurnParams();
            expect(additionalSwap).to.eq(true);
            expect(nextE280Swap).to.eq(0);
            expect(nextDragonXSwap).to.eq(capPerSwapDragonX);
            expect(nextBuyBurn).to.eq(buyBurnInterval);

            // const totalScaleBurnedToDate = await buyburn.totalScaleBurned();
            // const totalHeliosBurnedToDate = await buyburn.totalHeliosBurned();
            // const totalE280UsedToDate = await buyburn.totalE280Used();

            const e280AmountOut = await getQuoteV2(dragonx.target, e280.target, nextDragonXSwap);
            expect(e280AmountOut).to.be.greaterThan(capPerSwapE280);

            const incentiveFee = calculateBPS(capPerSwapE280, 30);
            const allocationAfterIncentive = capPerSwapE280 - incentiveFee;

            const heliosAmountIn = allocationAfterIncentive / 10n;
            const scaleAmountIn = allocationAfterIncentive - heliosAmountIn;
            const heliosAmountOut = await getQuoteV2(e280.target, helios.target, heliosAmountIn);
            const scaleAmountOut = await getQuoteV2(e280.target, scale.target, scaleAmountIn);

            const scaleAfterTax = scaleAmountOut - calculateBPS(scaleAmountOut, 700);
            const minScaleAmount = applySlippage(scaleAfterTax);
            const minHeliosAmount = applySlippage(heliosAmountOut);
            const deadline = await getDeadline();
            await expect(buyburn.connect(user).buyAndBurn(minScaleAmount, minHeliosAmount, 0, deadline)).to.changeTokenBalances(
                dragonx,
                [buyburn, user],
                [-capPerSwapDragonX, 0]
            );
            const timestamp = await time.latest();

            // expect(await buyburn.totalE280Used()).to.eq(totalE280UsedToDate + capPerSwapE280);
            expect(await buyburn.lastBuyBurn()).to.eq(timestamp);
            // expect(await buyburn.totalScaleBurned()).to.approximately(totalScaleBurnedToDate + scaleAfterTax, calculatePercentage(scaleAfterTax, 1));
            // expect(await buyburn.totalHeliosBurned()).to.eq(totalHeliosBurnedToDate + heliosAmountOut);
            await expect(buyburn.connect(user).buyAndBurn(0, 0, 0, 0)).to.be.revertedWithCustomError(buyburn, "Cooldown");
        });
        it("Should perform a buy burn using DragonX addition - dragonx check", async function () {
            const { buyburn, user, e280, helios, dragonx, scale, capPerSwapE280, capPerSwapDragonX, buyBurnInterval } = await loadFixture(
                buyBurnFundedWithBoth
            );
            const [additionalSwap, nextE280Swap, nextDragonXSwap, nextBuyBurn] = await buyburn.getBuyBurnParams();
            expect(additionalSwap).to.eq(true);
            expect(nextE280Swap).to.eq(capPerSwapE280 / 2n);
            expect(nextDragonXSwap).to.eq(capPerSwapDragonX);
            expect(nextBuyBurn).to.eq(buyBurnInterval);

            // const totalScaleBurnedToDate = await buyburn.totalScaleBurned();
            // const totalHeliosBurnedToDate = await buyburn.totalHeliosBurned();
            // const totalE280UsedToDate = await buyburn.totalE280Used();

            const e280AmountOut = await getQuoteV2(dragonx.target, e280.target, nextDragonXSwap);
            expect(e280AmountOut).to.be.greaterThan(capPerSwapE280);

            const incentiveFee = calculateBPS(capPerSwapE280, 30);
            const allocationAfterIncentive = capPerSwapE280 - incentiveFee;

            const heliosAmountIn = allocationAfterIncentive / 10n;
            const scaleAmountIn = allocationAfterIncentive - heliosAmountIn;
            const heliosAmountOut = await getQuoteV2(e280.target, helios.target, heliosAmountIn);
            const scaleAmountOut = await getQuoteV2(e280.target, scale.target, scaleAmountIn);

            const scaleAfterTax = scaleAmountOut - calculateBPS(scaleAmountOut, 700);
            const minScaleAmount = applySlippage(scaleAfterTax);
            const minHeliosAmount = applySlippage(heliosAmountOut);
            const deadline = await getDeadline();
            await expect(buyburn.connect(user).buyAndBurn(minScaleAmount, minHeliosAmount, 0, deadline)).to.changeTokenBalances(
                e280,
                [buyburn, user],
                [e280AmountOut - capPerSwapE280, incentiveFee]
            );
            const timestamp = await time.latest();

            // expect(await buyburn.totalE280Used()).to.eq(totalE280UsedToDate + capPerSwapE280);
            expect(await buyburn.lastBuyBurn()).to.eq(timestamp);
            // expect(await buyburn.totalScaleBurned()).to.approximately(totalScaleBurnedToDate + scaleAfterTax, calculatePercentage(scaleAfterTax, 1));
            // expect(await buyburn.totalHeliosBurned()).to.eq(totalHeliosBurnedToDate + heliosAmountOut);
            await expect(buyburn.connect(user).buyAndBurn(0, 0, 0, 0)).to.be.revertedWithCustomError(buyburn, "Cooldown");
        });
        it("Should perform a buy burn using DragonX addition - e280 check", async function () {
            const { buyburn, user, e280, helios, dragonx, scale, capPerSwapE280, capPerSwapDragonX, buyBurnInterval } = await loadFixture(
                buyBurnFundedWithBoth
            );
            const [additionalSwap, nextE280Swap, nextDragonXSwap, nextBuyBurn] = await buyburn.getBuyBurnParams();
            expect(additionalSwap).to.eq(true);
            expect(nextE280Swap).to.eq(capPerSwapE280 / 2n);
            expect(nextDragonXSwap).to.eq(capPerSwapDragonX);
            expect(nextBuyBurn).to.eq(buyBurnInterval);

            // const totalScaleBurnedToDate = await buyburn.totalScaleBurned();
            // const totalHeliosBurnedToDate = await buyburn.totalHeliosBurned();
            // const totalE280UsedToDate = await buyburn.totalE280Used();

            const e280AmountOut = await getQuoteV2(dragonx.target, e280.target, nextDragonXSwap);
            expect(e280AmountOut).to.be.greaterThan(capPerSwapE280);

            const incentiveFee = calculateBPS(capPerSwapE280, 30);
            const allocationAfterIncentive = capPerSwapE280 - incentiveFee;

            const heliosAmountIn = allocationAfterIncentive / 10n;
            const scaleAmountIn = allocationAfterIncentive - heliosAmountIn;
            const heliosAmountOut = await getQuoteV2(e280.target, helios.target, heliosAmountIn);
            const scaleAmountOut = await getQuoteV2(e280.target, scale.target, scaleAmountIn);

            const scaleAfterTax = scaleAmountOut - calculateBPS(scaleAmountOut, 700);
            const minScaleAmount = applySlippage(scaleAfterTax);
            const minHeliosAmount = applySlippage(heliosAmountOut);
            const deadline = await getDeadline();
            await expect(buyburn.connect(user).buyAndBurn(minScaleAmount, minHeliosAmount, 0, deadline)).to.changeTokenBalances(
                e280,
                [buyburn, user],
                [e280AmountOut - capPerSwapE280, incentiveFee]
            );
            const timestamp = await time.latest();

            // expect(await buyburn.totalE280Used()).to.eq(totalE280UsedToDate + capPerSwapE280);
            expect(await buyburn.lastBuyBurn()).to.eq(timestamp);
            // expect(await buyburn.totalScaleBurned()).to.approximately(totalScaleBurnedToDate + scaleAfterTax, calculatePercentage(scaleAfterTax, 1));
            // expect(await buyburn.totalHeliosBurned()).to.eq(totalHeliosBurnedToDate + heliosAmountOut);
            await expect(buyburn.connect(user).buyAndBurn(0, 0, 0, 0)).to.be.revertedWithCustomError(buyburn, "Cooldown");
        });
        it("Should perform consecutive buyBurns", async function () {
            const { buyburn, user, e280, helios, dragonx, scale, capPerSwapE280, capPerSwapDragonX, buyBurnInterval } = await loadFixture(
                buyBurnFullFundedWithBoth
            );
            {
                const [additionalSwap, nextE280Swap, nextDragonXSwap, nextBuyBurn] = await buyburn.getBuyBurnParams();
                expect(additionalSwap).to.eq(false);
                expect(nextE280Swap).to.eq(capPerSwapE280);
                expect(nextDragonXSwap).to.eq(capPerSwapDragonX);
                expect(nextBuyBurn).to.eq(buyBurnInterval);

                // const totalScaleBurnedToDate = await buyburn.totalScaleBurned();
                // const totalHeliosBurnedToDate = await buyburn.totalHeliosBurned();
                // const totalE280UsedToDate = await buyburn.totalE280Used();

                const incentiveFee = calculateBPS(nextE280Swap, 30);
                const allocationAfterIncentive = nextE280Swap - incentiveFee;

                const heliosAmountIn = allocationAfterIncentive / 10n;
                const scaleAmountIn = allocationAfterIncentive - heliosAmountIn;
                const heliosAmountOut = await getQuoteV2(e280.target, helios.target, heliosAmountIn);
                const scaleAmountOut = await getQuoteV2(e280.target, scale.target, scaleAmountIn);

                const scaleAfterTax = scaleAmountOut - calculateBPS(scaleAmountOut, 700);
                const minScaleAmount = applySlippage(scaleAfterTax);
                const minHeliosAmount = applySlippage(heliosAmountOut);
                const deadline = await getDeadline();
                await expect(buyburn.connect(user).buyAndBurn(minScaleAmount, minHeliosAmount, 0, deadline)).to.changeTokenBalances(
                    e280,
                    [buyburn, user],
                    [-nextE280Swap, incentiveFee]
                );
                const timestamp = await time.latest();

                // expect(await buyburn.totalE280Used()).to.eq(totalE280UsedToDate + capPerSwapE280);
                expect(await buyburn.lastBuyBurn()).to.eq(timestamp);
                // expect(await buyburn.totalScaleBurned()).to.approximately(
                // totalScaleBurnedToDate + scaleAfterTax,
                //     calculatePercentage(scaleAfterTax, 1)
                // );
                // expect(await buyburn.totalHeliosBurned()).to.eq(totalHeliosBurnedToDate + heliosAmountOut);

                await expect(buyburn.connect(user).buyAndBurn(0, 0, 0, 0)).to.be.revertedWithCustomError(buyburn, "Cooldown");
            }
            await time.increase(buyBurnInterval);
            {
                const [additionalSwap, nextE280Swap, nextDragonXSwap] = await buyburn.getBuyBurnParams();
                expect(additionalSwap).to.eq(true);
                expect(nextE280Swap).to.eq(capPerSwapE280 / 2n);
                expect(nextDragonXSwap).to.eq(capPerSwapDragonX);

                // const totalScaleBurnedToDate = await buyburn.totalScaleBurned();
                // const totalHeliosBurnedToDate = await buyburn.totalHeliosBurned();
                // const totalE280UsedToDate = await buyburn.totalE280Used();

                const e280AmountOut = await getQuoteV2(dragonx.target, e280.target, nextDragonXSwap);
                expect(e280AmountOut).to.be.greaterThan(capPerSwapE280);

                const incentiveFee = calculateBPS(capPerSwapE280, 30);
                const allocationAfterIncentive = capPerSwapE280 - incentiveFee;

                const heliosAmountIn = allocationAfterIncentive / 10n;
                const scaleAmountIn = allocationAfterIncentive - heliosAmountIn;
                const heliosAmountOut = await getQuoteV2(e280.target, helios.target, heliosAmountIn);
                const scaleAmountOut = await getQuoteV2(e280.target, scale.target, scaleAmountIn);

                const scaleAfterTax = scaleAmountOut - calculateBPS(scaleAmountOut, 700);
                const minScaleAmount = applySlippage(scaleAfterTax);
                const minHeliosAmount = applySlippage(heliosAmountOut);
                const deadline = await getDeadline();
                await expect(buyburn.connect(user).buyAndBurn(minScaleAmount, minHeliosAmount, 0, deadline)).to.changeTokenBalances(
                    e280,
                    [buyburn, user],
                    [e280AmountOut - capPerSwapE280, incentiveFee]
                );
                const timestamp = await time.latest();

                // expect(await buyburn.totalE280Used()).to.eq(totalE280UsedToDate + capPerSwapE280);
                expect(await buyburn.lastBuyBurn()).to.eq(timestamp);
                // expect(await buyburn.totalScaleBurned()).to.approximately(
                // totalScaleBurnedToDate + scaleAfterTax,
                //     calculatePercentage(scaleAfterTax, 1)
                // );
                // expect(await buyburn.totalHeliosBurned()).to.eq(totalHeliosBurnedToDate + heliosAmountOut);

                await expect(buyburn.connect(user).buyAndBurn(0, 0, 0, 0)).to.be.revertedWithCustomError(buyburn, "Cooldown");
            }
            await time.increase(buyBurnInterval);
            {
                const [additionalSwap, nextE280Swap, nextDragonXSwap] = await buyburn.getBuyBurnParams();
                expect(additionalSwap).to.eq(false);
                expect(nextE280Swap).to.eq(capPerSwapE280);
                expect(nextDragonXSwap).to.eq(capPerSwapDragonX);

                // const totalScaleBurnedToDate = await buyburn.totalScaleBurned();
                // const totalHeliosBurnedToDate = await buyburn.totalHeliosBurned();
                // const totalE280UsedToDate = await buyburn.totalE280Used();

                const incentiveFee = calculateBPS(nextE280Swap, 30);
                const allocationAfterIncentive = nextE280Swap - incentiveFee;

                const heliosAmountIn = allocationAfterIncentive / 10n;
                const scaleAmountIn = allocationAfterIncentive - heliosAmountIn;
                const heliosAmountOut = await getQuoteV2(e280.target, helios.target, heliosAmountIn);
                const scaleAmountOut = await getQuoteV2(e280.target, scale.target, scaleAmountIn);

                const scaleAfterTax = scaleAmountOut - calculateBPS(scaleAmountOut, 700);
                const minScaleAmount = applySlippage(scaleAfterTax);
                const minHeliosAmount = applySlippage(heliosAmountOut);
                const deadline = await getDeadline();
                await expect(buyburn.connect(user).buyAndBurn(minScaleAmount, minHeliosAmount, 0, deadline)).to.changeTokenBalances(
                    e280,
                    [buyburn, user],
                    [-nextE280Swap, incentiveFee]
                );
                const timestamp = await time.latest();

                // expect(await buyburn.totalE280Used()).to.eq(totalE280UsedToDate + capPerSwapE280);
                expect(await buyburn.lastBuyBurn()).to.eq(timestamp);
                // expect(await buyburn.totalScaleBurned()).to.approximately(
                // totalScaleBurnedToDate + scaleAfterTax,
                //     calculatePercentage(scaleAfterTax, 1)
                // );
                // expect(await buyburn.totalHeliosBurned()).to.eq(totalHeliosBurnedToDate + heliosAmountOut);
                await expect(buyburn.connect(user).buyAndBurn(0, 0, 0, 0)).to.be.revertedWithCustomError(buyburn, "Cooldown");
            }
        });
    });
});
