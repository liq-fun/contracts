// SPX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*

OUT OF SCOPE FOR ANY AUDITING

*/

import "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UniswapV3Swapper {
    IQuoter public quoter;
    ISwapRouter public swapRouter;

    address public constant WETH = 0x4200000000000000000000000000000000000006;

    uint256 public LIQUIDATION_FEE = 5;

    constructor(address _quoter, address _swapRouter) {
        quoter = IQuoter(_quoter);
        swapRouter = ISwapRouter(_swapRouter);
    }

    function _quoteAmountOutV3Pair(
        address tokenIn,
        uint24 fee,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        amountOut = quoter.quoteExactInputSingle(
            tokenIn,
            WETH,
            fee,
            amountIn,
            0
        );
    }

    function _quotePriceV3Pair(
        address tokenOut,
        uint24 fee,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        amountOut = quoter.quoteExactOutputSingle(
            WETH,
            tokenOut,
            fee,
            amountIn,
            0
        );
    }

    function _swapAndLiquifyTokenV3(
        address tokenIn,
        uint24 fee,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256 ethOut) {
        IERC20(tokenIn).approve(address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: WETH,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            });

        uint256 prevBal = address(this).balance;

        swapRouter.exactInputSingle(params);

        uint256 newBal = address(this).balance;
        uint256 liquidationFee = ((newBal - prevBal) * LIQUIDATION_FEE) / 100;
        ethOut = (newBal - prevBal) - liquidationFee;
    }

    function _swapETHForTokenV3(
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256 tokensOut) {
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
            .ExactOutputSingleParams({
                tokenIn: WETH,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: amountOutMin,
                amountInMaximum: amountIn,
                sqrtPriceLimitX96: 0
            });

        uint256 prevBal = IERC20(tokenOut).balanceOf(address(this));

        swapRouter.exactOutputSingle{value: amountIn}(params);

        uint256 newBal = IERC20(tokenOut).balanceOf(address(this));
        tokensOut = newBal - prevBal;
    }
}
