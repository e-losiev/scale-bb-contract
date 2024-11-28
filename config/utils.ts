import routerAbi from "@uniswap/v2-periphery/build/UniswapV2Router02.json";
import pairV2Abi from "@uniswap/v2-periphery/build/IUniswapV2Pair.json";
import factoryV2Abi from "@uniswap/v2-periphery/build/IUniswapV2Factory.json";
import { time } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { ethers } from "hardhat";
import { UNISWAP_V2_ROUTER, UNISWAP_V2_FACTORY, SLIPPAGE, DEBUG } from "./constants";

export async function getPrefundedWallet(address: string, fundingUser: any) {
    const wallet = await ethers.getImpersonatedSigner(address);
    await fundingUser.sendTransaction({ value: ethers.parseEther("0.5"), to: wallet });
    return wallet;
}

export async function fundWallet(token: any, userFrom: string, userTo: any) {
    const user = await ethers.getImpersonatedSigner(userFrom);
    await userTo.sendTransaction({ value: ethers.parseEther("0.5"), to: user });
    const balance = await token.balanceOf(user);
    await token.connect(user).transfer(userTo, balance);
    const newBalance = await token.balanceOf(userTo);
    if (newBalance === 0n) throw new Error(`Zero balance for user ...${userFrom.slice(-5)}`);
    return newBalance;
}

export async function getDeadline(seconds: number = 50) {
    const timestamp = await time.latest();
    return timestamp + seconds;
}

export function calculatePercentage(amount: bigint, percentage: number) {
    return (amount * BigInt(Math.floor(percentage * 100))) / 10000n;
}

export function applySlippage(amount: bigint) {
    return calculatePercentage(amount, 100 - SLIPPAGE);
}

export function calculateBPS(amount: bigint, bps: number) {
    return (amount * BigInt(bps)) / 10000n;
}

export async function passDays(days: number, delta: number = 0) {
    await time.increase(86400 * days + delta);
}

export async function passHours(hours: number) {
    await time.increase(3600 * hours);
}

export async function getPairAddress(tokenAddress: any, scaleAddress: any) {
    const factoryV2 = new ethers.Contract(UNISWAP_V2_FACTORY, factoryV2Abi.abi, ethers.provider);
    const pairAddress = await factoryV2.getPair(scaleAddress, tokenAddress);
    const pair = new ethers.Contract(pairAddress, pairV2Abi.abi, ethers.provider);
    return pair;
}

export async function getQuoteV2(tokenIn: any, tokenOut: any, amountIn: bigint, showValues: boolean = false) {
    const routerV2 = new ethers.Contract(UNISWAP_V2_ROUTER, routerAbi.abi, ethers.provider);
    const [, amountOut] = await routerV2.getAmountsOut(amountIn, [tokenIn, tokenOut]);
    if (showValues || DEBUG) {
        console.log("Amount in: ", ethers.formatEther(amountIn));
        console.log("Estimated amount out:", ethers.formatEther(amountOut));
    }

    return amountOut;
}
