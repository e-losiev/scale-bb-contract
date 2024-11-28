import { loadFixture, time } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { ethers } from "hardhat";
import { fundWallet, getPrefundedWallet } from "./utils";
import { DRAGONX, DRAGONX_HOLDER, E280, E280_ADMIN, E280_HOLDER, SCALE } from "./constants";

export async function deployFixture() {
    const [deployer, owner, user, user2] = await ethers.getSigners();
    const e280Admin = await getPrefundedWallet(E280_ADMIN, deployer);

    /// Tokens
    const scale = await ethers.getContractAt("IERC20", SCALE);
    const e280 = await ethers.getContractAt("IElement280", E280);
    const dragonx = await ethers.getContractAt("IERC20", DRAGONX);

    const buyburnFactory = await ethers.getContractFactory("ScaleBuyBurn");
    const buyburn = await buyburnFactory.deploy(owner);

    const userE280Balance = await fundWallet(e280, E280_HOLDER, user);
    const userDragonXBalance = await fundWallet(dragonx, DRAGONX_HOLDER, user);

    await e280.connect(e280Admin).setWhitelistFrom(buyburn, true);
    await e280.connect(e280Admin).setWhitelistTo(buyburn, true);
    await buyburn.connect(owner).setWhitelisted([user], true);

    const incentiveFeeBps = await buyburn.incentiveFeeBps();
    const capPerSwapE280 = await buyburn.capPerSwapE280();
    const capPerSwapDragonX = await buyburn.capPerSwapDragonX();
    const buyBurnInterval = await buyburn.buyBurnInterval();

    return {
        buyburn,
        scale,
        e280,
        dragonx,
        deployer,
        owner,
        user,
        user2,
        userE280Balance,
        userDragonXBalance,
        incentiveFeeBps,
        capPerSwapE280,
        capPerSwapDragonX,
        buyBurnInterval,
    };
}

export async function buyBurnFundedE280Fixture() {
    const data = await loadFixture(deployFixture);
    const { e280, user, buyburn, userE280Balance } = data;
    await e280.connect(user).transfer(buyburn, userE280Balance);
    const buyburnBalance = await e280.balanceOf(buyburn);
    return { ...data, buyburnBalance };
}
export async function buyBurnFundedDragonXFixture() {
    const data = await loadFixture(deployFixture);
    const { dragonx, user, buyburn, userDragonXBalance } = data;
    await dragonx.connect(user).transfer(buyburn, userDragonXBalance);
    const buyburnBalance = await dragonx.balanceOf(buyburn);
    return { ...data, buyburnBalance };
}

export async function buyBurnFundedWithBoth() {
    const data = await loadFixture(buyBurnFundedDragonXFixture);
    const { e280, user, buyburn, capPerSwapE280 } = data;
    await e280.connect(user).transfer(buyburn, capPerSwapE280 / 2n);
    return { ...data };
}

export async function buyBurnFullFundedWithBoth() {
    const data = await loadFixture(buyBurnFundedDragonXFixture);
    const { e280, user, buyburn, capPerSwapE280 } = data;
    await e280.connect(user).transfer(buyburn, capPerSwapE280 + capPerSwapE280 / 2n);
    return { ...data };
}
