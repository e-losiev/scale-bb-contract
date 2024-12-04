import { ethers } from "hardhat";
import { E280_ADMIN, SCALE, E280, HELIOS, DRAGONX, E280_HOLDER, DRAGONX_HOLDER } from "../../config/constants";
import { fundWallet, getPrefundedWallet } from "../../config/utils";

async function main() {
    const [deployer, hh2, hh3] = await ethers.getSigners();
    const e280Admin = await getPrefundedWallet(E280_ADMIN, deployer);

    /// Tokens
    const e280 = await ethers.getContractAt("IElement280", E280);
    const dragonx = await ethers.getContractAt("IERC20", DRAGONX);

    const buyburnFactory = await ethers.getContractFactory("ScaleBuyBurn");
    const buyburn = await buyburnFactory.deploy(deployer);

    await fundWallet(e280, E280_HOLDER, hh2);
    await fundWallet(dragonx, DRAGONX_HOLDER, hh2);
    await e280.connect(e280Admin).setWhitelistFrom(buyburn, true);
    await e280.connect(e280Admin).setWhitelistTo(buyburn, true);
    await buyburn.connect(deployer).setWhitelisted([hh2], true);

    const currentTimestamp = Math.floor(new Date().getTime() / 1000);
    await ethers.provider.send("evm_setNextBlockTimestamp", [currentTimestamp]);

    console.log(`ScaleBuyBurn deployed to: ${buyburn.target}`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
