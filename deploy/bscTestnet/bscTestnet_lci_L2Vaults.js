const { ethers } = require("hardhat");
const { common, bscTestnet: network_ } = require("../../parameters/testnet");

module.exports = async ({ deployments }) => {

  const vaultArtifact = await deployments.getArtifact("BscVaultTest");
  const vaultIface = new ethers.utils.Interface(JSON.stringify(vaultArtifact.abi));

  const bscVaultFactory = await ethers.getContract("BscVaultFactory");
  const totalVaults = await bscVaultFactory.totalVaults();

  const dataUSDTUSDC = vaultIface.encodeFunctionData("initialize", [
    "LCI L2 USDT-USDC", "lciL2USDTC",
    network_.PancakeSwap.Farm_USDT_USDC_pid,
    common.treasury, common.admin,
  ]);

  if (totalVaults < 1) {
    console.log("Now deploying USDTUSDCVault ...");
    const tx = await bscVaultFactory.createVault(dataUSDTUSDC);
    await tx.wait();
    const USDTUSDCVaultAddr = await bscVaultFactory.getVault((await bscVaultFactory.totalVaults()).sub(1))
    console.log("  USDTUSDCVaultAddr: ", USDTUSDCVaultAddr);
  }

  if (totalVaults < 2) {
    console.log("Now deploying USDTBUSDVault ...");
    const dataUSDTBUSD= vaultIface.encodeFunctionData("initialize", [
      "LCI L2 USDT-BUSD", "lciL2USDTB",
      network_.PancakeSwap.Farm_USDT_BUSD_pid,
      common.treasury, common.admin,
    ]);

    const tx = await bscVaultFactory.createVault(dataUSDTBUSD);
    await tx.wait();
    const USDTBUSDVaultAddr = await bscVaultFactory.getVault((await bscVaultFactory.totalVaults()).sub(1))
    console.log("  USDTBUSDVaultAddr: ", USDTBUSDVaultAddr);
  }

  if (totalVaults < 3) {
    console.log("Now deploying USDCBUSDVault ...");
    const dataUSDCBUSD= vaultIface.encodeFunctionData("initialize", [
      "LCI L2 USDC-BUSD", "lciL2USDCB",
      network_.PancakeSwap.Farm_USDC_BUSD_pid,
      common.treasury, common.admin,
    ]);

    const tx = await bscVaultFactory.createVault(dataUSDCBUSD);
    await tx.wait();
    const USDCBUSDVaultAddr = await bscVaultFactory.getVault((await bscVaultFactory.totalVaults()).sub(1))
    console.log("  USDCBUSDVaultAddr: ", USDCBUSDVaultAddr);
  }

  // Verify the contracts
  try {
    await run("verify:verify", {
      address: await avaxVaultFactory.getVault(0),
      constructorArguments: [
        await avaxVaultFactory.getBeacon(),
        dataUSDTUSDC
      ],
      contract: "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol:BeaconProxy",
    });
  } catch(e) {
  }

};
module.exports.tags = ["bscTestnet_lci_L2Vaults"];
