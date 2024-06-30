// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/ISwapRouter02.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IUniversalRouter.sol";
import "./interfaces/IUniswapV2.sol";
import "./interfaces/IQuoter.sol";

import "../permit2/src/interfaces/IPermit2.sol";

import {Commands} from "./Commands.sol";

contract SwapRouterHelper {
    // 0x2626664c2603336E57B271c5C0b26F421741e481
    ISwapRouter02 public router;

    // 0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD
    IUniversalRouter public universalRouter;

    // 0x222ca98f00ed15b1fae10b61c277703a194cf5d2
    IQuoter public quoter;

    IPermit2 public permit2;

    // 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6
    IUniswapV2Factory public factoryV2;

    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant PERMIT2 =
        0x000000000022D473030F116dDEE9F6B43aC78BA3;

    IWETH public weth = IWETH(WETH);

    constructor(
        address _router,
        address _universalRouter,
        address _quoter,
        address _factoryV2
    ) {
        router = ISwapRouter02(_router);
        universalRouter = IUniversalRouter(_universalRouter);
        permit2 = IPermit2(PERMIT2);
        quoter = IQuoter(_quoter);
        factoryV2 = IUniswapV2Factory(_factoryV2);
    }

    function _swapTokensForETHV2(
        address tokenIn,
        uint256 amountIn,
        uint256 ethOutMin
    ) internal returns (uint256 wethOut) {
        permit2.approve(
            tokenIn,
            address(universalRouter),
            type(uint160).max,
            type(uint48).max
        );

        IERC20(tokenIn).transfer(address(universalRouter), amountIn);

        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.V2_SWAP_EXACT_IN))
        );
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = WETH;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(this), amountIn, ethOutMin, path, false);

        uint256 prevBalance = weth.balanceOf(address(this));

        universalRouter.execute(commands, inputs);

        wethOut = weth.balanceOf(address(this)) - prevBalance;
    }

    function _swapETHForTokensV2(
        address tokenOut,
        uint256 ethIn,
        uint256 tokensOutMin
    ) internal returns (uint256 tokensOut) {
        permit2.approve(
            WETH,
            address(universalRouter),
            type(uint160).max,
            type(uint48).max
        );

        IERC20(WETH).transfer(address(universalRouter), ethIn);

        bytes memory commands = abi.encodePacked(
            bytes1(uint8(Commands.V2_SWAP_EXACT_IN))
        );
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = tokenOut;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(this), ethIn, tokensOutMin, path, false);

        uint256 prevBalance = IERC20(tokenOut).balanceOf(address(this));

        universalRouter.execute(commands, inputs);

        tokensOut = IERC20(tokenOut).balanceOf(address(this)) - prevBalance;
    }

    // Assumes the contract holds tokenIn and the amountIn already
    function _swapTokensForETHV3(
        address tokenIn,
        uint256 amountIn,
        uint256 ethOutMin,
        uint24 fee
    ) internal returns (uint256 wethOut) {
        IERC20(tokenIn).approve(address(router), amountIn);

        uint256 prevBal = weth.balanceOf(address(this));

        router.exactInputSingle(
            ISwapRouter02.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: WETH,
                fee: fee,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: ethOutMin,
                sqrtPriceLimitX96: 0
            })
        );

        wethOut = weth.balanceOf(address(this)) - prevBal;
    }

    function _swapETHForTokensV3(
        address tokenOut,
        uint256 wethIn,
        uint256 tokenOutMin,
        uint24 fee
    ) internal returns (uint256 tokensOut) {
        IERC20(WETH).approve(address(router), wethIn);

        uint256 prevBal = IERC20(tokenOut).balanceOf(address(this));

        router.exactInputSingle(
            ISwapRouter02.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                amountIn: wethIn,
                amountOutMinimum: tokenOutMin,
                sqrtPriceLimitX96: 0
            })
        );

        tokensOut = IERC20(tokenOut).balanceOf(address(this)) - prevBal;
    }

    function _quoteTokensToETHV2(
        address token,
        uint256 amountIn
    ) internal view returns (uint256 amountOut) {
        IUniswapV2Pair pair = IUniswapV2Pair(factoryV2.getPair(WETH, token));
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        (uint112 reserveInput, uint112 reserveOutput) = pair.token0() == token
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
        amountOut = getAmountOut(amountIn, reserveInput, reserveOutput);
    }

    function _quoteETHToTokensV2(
        address token,
        uint256 amountIn
    ) internal view returns (uint256 amountOut) {
        IUniswapV2Pair pair = IUniswapV2Pair(factoryV2.getPair(WETH, token));
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        (uint112 reserveInput, uint112 reserveOutput) = pair.token0() == WETH
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
        amountOut = getAmountOut(amountIn, reserveInput, reserveOutput);
    }

    function getAmountOut(
        uint256 amountIn,
        uint112 reserveIn,
        uint112 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function _quoteTokensToETHV3(
        address tokenIn,
        uint24 fee,
        uint256 amountIn
    ) internal view returns (uint256 amountOut) {
        (amountOut, , , ) = quoter.quoteExactInputSingle(
            IQuoter.QuoteExactInputSingleParams(tokenIn, WETH, amountIn, fee, 0)
        );
    }

    function _quoteETHToTokensV3(
        address tokenIn,
        uint24 fee,
        uint256 amountIn
    ) internal view returns (uint256 amountOut) {
        (amountOut, , , ) = quoter.quoteExactInputSingle(
            IQuoter.QuoteExactInputSingleParams(WETH, tokenIn, amountIn, fee, 0)
        );
    }
}
