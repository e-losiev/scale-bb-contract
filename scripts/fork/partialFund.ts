import { ethers } from "hardhat";
import { E280_ADMIN, SCALE, E280, HELIOS, DRAGONX, E280_HOLDER, DRAGONX_HOLDER } from "../../config/constants";
import { fundWallet, getPrefundedWallet } from "../../config/utils";

async function main() {
    const [deployer, hh2, hh3] = await ethers.getSigners();

    /// Tokens
    const e280 = await ethers.getContractAt("IElement280", E280);
    const dragonx = await ethers.getContractAt("IERC20", DRAGONX);

    const buyburn = await ethers.getContractAt("ScaleBuyBurn", "0x364C7188028348566E38D762f6095741c49f492B");
    const capPerSwapE280 = await buyburn.capPerSwapE280();
    const capPerSwapDragonX = await buyburn.capPerSwapDragonX();

    await e280.connect(hh2).transfer(buyburn, capPerSwapE280 / 2n);
    await dragonx.connect(hh2).transfer(buyburn, capPerSwapDragonX * 2n);

    console.log(`Funded Buy & Burn`);
    console.log(await buyburn.owner());
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
