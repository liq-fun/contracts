import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const LiqFunGameManagerModule = buildModule("LiqFunGameManagerModule", (m) => {
  const gameManager = m.contract("LiqFunGameManager", [
    "0x86FA9cC0a10Fc89B649A63D36918747eC2D37C28",
    "0x2626664c2603336E57B271c5C0b26F421741e481",
    "0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD",
    "0x222ca98f00ed15b1fae10b61c277703a194cf5d2",
    "0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6",
  ]);

  return { gameManager };
});

export default LiqFunGameManagerModule;
