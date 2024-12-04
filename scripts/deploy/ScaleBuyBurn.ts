import { ethers, run } from "hardhat";

async function main() {
    const OWNER = "";
    const buyburnFactory = await ethers.getContractFactory("ScaleBuyBurn");
    const buyburn = await buyburnFactory.deploy(OWNER);

    console.log(`ScaleBuyBurn deployed to: ${buyburn.target}`);

    // await run("verify:verify", {
    //     address: "0xBF6659a49b59104d962CE9085708D29649be12C7",
    //     constructorArguments: [OWNER],
    // });
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
