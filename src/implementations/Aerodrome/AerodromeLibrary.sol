// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./interfaces/IRouter.sol";
import "./interfaces/IGauge.sol";
import "./interfaces/IWETH.sol";

library AerodromeLibrary {

    function getAmountsOut(
        address router,
        address inputToken,
        address outputToken,
        address pool0,
        uint256 amountInput
    ) internal view returns (uint256) {

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0].from = inputToken;
        routes[0].to = outputToken;
        routes[0].stable = IPool(pool0).stable();
        routes[0].factory = IPool(pool0).factory();

        uint256[] memory amounts = IRouter(router).getAmountsOut(amountInput, routes);

        return amounts[1];
    }

    function getAmountsOut(
        address router,
        address inputToken,
        address middleToken,
        address outputToken,
        address pool0,
        address pool1,
        uint256 amountInput
    ) internal view returns (uint256) {

        IRouter.Route[] memory routes = new IRouter.Route[](2);
        routes[0].from = inputToken;
        routes[0].to = middleToken;
        routes[0].stable = IPool(pool0).stable();
        routes[0].factory = IPool(pool0).factory();
        routes[1].from = middleToken;
        routes[1].to = outputToken;
        routes[1].stable = IPool(pool1).stable();
        routes[1].factory = IPool(pool1).factory();

        uint256[] memory amounts = IRouter(router).getAmountsOut(amountInput, routes);

        return amounts[2];
    }

    function singleSwap(
        address router,
        address inputToken,
        address outputToken,
        address pool0,
        uint256 amountInput,
        uint256 amountOutMin,
        address recipient
    ) internal returns (uint256) {

        IERC20(inputToken).approve(router, amountInput);

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0].from = inputToken;
        routes[0].to = outputToken;
        routes[0].stable = IPool(pool0).stable();
        routes[0].factory = IPool(pool0).factory();

        uint256[] memory amounts = IRouter(router).swapExactTokensForTokens(
            amountInput,
            amountOutMin,
            routes,
            recipient,
            block.timestamp
        );

        return amounts[1];
    }

    function multiSwap(
        address router,
        address inputToken,
        address middleToken,
        address outputToken,
        address pool0,
        address pool1,
        uint256 amountInput,
        uint256 amountOutMin,
        address recipient
    ) internal returns (uint256) {

        IERC20(inputToken).approve(router, amountInput);

        IRouter.Route[] memory routes = new IRouter.Route[](2);
        routes[0].from = inputToken;
        routes[0].to = middleToken;
        routes[0].stable = IPool(pool0).stable();
        routes[0].factory = IPool(pool0).factory();
        routes[1].from = middleToken;
        routes[1].to = outputToken;
        routes[1].stable = IPool(pool1).stable();
        routes[1].factory = IPool(pool1).factory();

        uint256[] memory amounts = IRouter(router).swapExactTokensForTokens(
            amountInput,
            amountOutMin,
            routes,
            recipient,
            block.timestamp
        );

        return amounts[2];
    }

}