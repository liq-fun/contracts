import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers";
import { impersonateAccount, mine } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers";
import { assert, expect } from "chai";
import { parseEther } from "viem";

describe("LiqFunGameManager", function () {
    async function deployLiqGame() {
        const [owner, addr1, addr2] = await hre.viem.getWalletClients();

        await impersonateAccount("0x44f6498d1403321890f3f2917e00f22dbde3577a");

        const tokenHolder = await hre.viem.getWalletClient("0x44f6498d1403321890f3f2917e00f22dbde3577a");

        const liqGame = await hre.viem.deployContract("LiqFunGameManager", [
            "0x86FA9cC0a10Fc89B649A63D36918747eC2D37C28",
            "0x2626664c2603336E57B271c5C0b26F421741e481",
            "0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD",
            "0x222ca98f00ed15b1fae10b61c277703a194cf5d2",
            "0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6",
        ]);

        const frame = await hre.viem.getContractAt("IERC20", "0x91F45aa2BdE7393e0AF1CC674FFE75d746b93567");

        const floppa = await hre.viem.getContractAt("IERC20",
            "0x776aAef8D8760129A0398CF8674EE28cefc0EAb9"
        );

        const degen = await hre.viem.getContractAt("IERC20",
            "0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed"
        );

        const weth = await hre.viem.getContractAt("IERC20",
            "0x4200000000000000000000000000000000000006"
        );

        await degen.write.approve([
            liqGame.address,
            parseEther("10000000")
        ], {
            account: tokenHolder.account
        });

        const publicClient = await hre.viem.getPublicClient();

        return {
            liqGame,
            publicClient,
            owner,
            addr1,
            addr2,
            tokenHolder,
            frame,
            floppa,
            degen,
            weth
        }
    }

    describe("Deployment", function () {
        it("Should LIQUIDATION_FEE properly", async function () {
            const { liqGame, publicClient } = await loadFixture(deployLiqGame);

            assert.equal(await liqGame.read.LIQUIDATION_FEE(), 5n);
        });

        it("Should set CREATION_FEE properly", async function () {
            const { liqGame, publicClient } = await loadFixture(deployLiqGame);

            assert.equal(await liqGame.read.CREATION_FEE(), parseEther("0.005"));
        })
    });

    describe("Game Creation", function () {
        it("Should allow game creation", async function () {
            const { liqGame, publicClient, owner, addr1, addr2, frame, floppa, tokenHolder } = await loadFixture(deployLiqGame);

            await liqGame.write.createGame([
                frame.address,
                floppa.address,
                3n,
                2n,
                10000n,
                0n,
                0n
            ]);

            expect(await liqGame.read.games([floppa.address, frame.address])).to.not.equal(null);
        });

        it("Should allow game creation and completetion", async function () {
            const { liqGame, publicClient, owner, addr1, addr2, frame, floppa, tokenHolder } = await loadFixture(deployLiqGame);

            const sb = await publicClient.getBlockNumber();

            await expect(liqGame.write.createGame([
                frame.address,
                floppa.address,
                3n,
                2n,
                10000n,
                0n,
                sb
            ], {
                account: owner.account,
                value: parseEther("0.005")
            })).not.to.be.reverted;

            await mine(10);

            await frame.write.approve([
                liqGame.address,
                parseEther("10000000")
            ], {
                account: tokenHolder.account
            });

            await floppa.write.approve([
                liqGame.address,
                parseEther("10000000")
            ], {
                account: tokenHolder.account
            });

            await liqGame.write.stakeInGame([
                floppa.address,
                frame.address,
                parseEther("10000"),
                frame.address
            ], {
                account: tokenHolder.account
            });

            expect(await frame.read.balanceOf([liqGame.address])).to.equal(parseEther("10000"));

            await liqGame.write.stakeInGame([
                floppa.address,
                frame.address,
                parseEther("100000"),
                floppa.address
            ], {
                account: tokenHolder.account
            });

            expect(await floppa.read.balanceOf([liqGame.address])).to.equal(parseEther("100000"));

            await mine(100000);

            const [gameHash, startBlock, endBlock, token1Amount, token2Amount, token1PoolVersion, token2PoolVersion, token1PoolFee, token2PoolFee, hasCompleted] = await liqGame.read.games([floppa.address, frame.address]) as any;

            expect(gameHash).to.not.equal(null);
            expect(startBlock).to.equal(sb);
            expect(endBlock).to.equal(sb + 120n);
            expect(hasCompleted).to.equal(false);

            const cb = await publicClient.getBlockNumber();
            expect(parseInt(cb.toString())).to.be.greaterThan(parseInt(endBlock.toString()));

            liqGame.write.completeGame([
                floppa.address,
                frame.address
            ]);

        });
    })
})