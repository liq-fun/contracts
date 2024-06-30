// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*

OUT OF SCOPE FOR ANY AUDITING

*/

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract UniswapV2Swapper {
    IUniswapV2Router02 public UNISWAP_V2_ROUTER;

    address public constant _WETH = 0x4200000000000000000000000000000000000006;

    uint256 public _LIQUIDATION_FEE = 5;

    constructor(address _uniswapV2Router) {
        UNISWAP_V2_ROUTER = IUniswapV2Router02(_uniswapV2Router);
    }

    function _quoteAmountOutV2Pair(
        address tokenIn,
        uint256 amountIn
    ) internal view returns (uint256 amountOut) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = _WETH;

        uint256[] memory amountsOut = UNISWAP_V2_ROUTER.getAmountsOut(
            amountIn,
            path
        );
        amountOut = amountsOut[1];
    }

    function _quotePriceV2Pair(
        address tokenOut,
        uint256 amountIn
    ) internal view returns (uint256 amountOut) {
        address[] memory path = new address[](2);
        path[0] = _WETH;
        path[1] = tokenOut;

        uint256[] memory amountsOut = UNISWAP_V2_ROUTER.getAmountsOut(
            amountIn,
            path
        );

        amountOut = amountsOut[1];
    }

    function _swapAndLiquifyTokenV2(
        address tokenToLiquidate,
        uint256 amountToLiquidate,
        uint256 amountOutMin
    ) internal returns (uint256 ethOut) {
        IERC20(tokenToLiquidate).approve(
            address(UNISWAP_V2_ROUTER),
            amountToLiquidate
        );

        address[] memory path = new address[](2);
        path[0] = tokenToLiquidate;
        path[1] = _WETH;

        uint256 prevBal = address(this).balance;

        UNISWAP_V2_ROUTER.swapExactTokensForETH(
            amountToLiquidate,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );

        uint256 newBal = address(this).balance;

        uint256 liquidationFee = ((newBal - prevBal) * _LIQUIDATION_FEE) / 100;
        ethOut = (newBal - prevBal) - liquidationFee;
    }

    function _swapETHForTokenV2(
        address tokenToBuy,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256 tokensOut) {
        address[] memory path = new address[](2);
        path[0] = _WETH;
        path[1] = tokenToBuy;

        uint256 prevBal = IERC20(tokenToBuy).balanceOf(address(this));

        UNISWAP_V2_ROUTER.swapExactETHForTokens{value: amountIn}(
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );

        uint256 newBal = IERC20(tokenToBuy).balanceOf(address(this));
        tokensOut = newBal - prevBal;
    }
}
