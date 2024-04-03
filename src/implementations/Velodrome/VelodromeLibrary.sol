// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./interfaces/IRouter.sol";
import "./interfaces/IPool.sol";

library VelodromeLibrary {

    function getAmountsOut(
        address velodromeRouter,
        address inputToken,
        address outputToken,
        bool isStablePair0,
        address pool0,
        uint256 amountInput
    ) internal view returns (uint256) {

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0].from = inputToken;
        routes[0].to = outputToken;
        routes[0].stable = isStablePair0;
        routes[0].factory = IPool(pool0).factory();

        uint256[] memory amounts = IRouter(velodromeRouter).getAmountsOut(amountInput, routes);

        return amounts[1];
    }

    function getAmountsOut(
        address velodromeRouter,
        address inputToken,
        address middleToken,
        address outputToken,
        bool isStablePair0,
        bool isStablePair1,
        address pool0,
        address pool1,
        uint256 amountInput
    ) internal view returns (uint256) {

        IRouter.Route[] memory routes = new IRouter.Route[](2);
        routes[0].from = inputToken;
        routes[0].to = middleToken;
        routes[0].stable = isStablePair0;
        routes[0].factory = IPool(pool0).factory();
        routes[1].from = middleToken;
        routes[1].to = outputToken;
        routes[1].stable = isStablePair1;
        routes[1].factory = IPool(pool1).factory();

        uint256[] memory amounts = IRouter(velodromeRouter).getAmountsOut(amountInput, routes);

        return amounts[2];
    }

    function singleSwap(
        address velodromeRouter,
        address inputToken,
        address outputToken,
        bool isStablePair0,
        address pool0,
        uint256 amountInput,
        uint256 amountOutMin,
        address recipient
    ) internal returns (uint256) {

        IERC20(inputToken).approve(velodromeRouter, amountInput);

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0].from = inputToken;
        routes[0].to = outputToken;
        routes[0].stable = isStablePair0;
        routes[0].factory = IPool(pool0).factory();

        uint256[] memory amounts = IRouter(velodromeRouter).swapExactTokensForTokens(
            amountInput,
            amountOutMin,
            routes,
            recipient,
            block.timestamp
        );

        return amounts[1];
    }

    function multiSwap(
        address velodromeRouter,
        address inputToken,
        address middleToken,
        address outputToken,
        bool isStablePair0,
        bool isStablePair1,
        address pool0,
        address pool1,
        uint256 amountInput,
        uint256 amountOutMin,
        address recipient
    ) internal returns (uint256) {

        IERC20(inputToken).approve(velodromeRouter, amountInput);

        IRouter.Route[] memory routes = new IRouter.Route[](2);
        routes[0].from = inputToken;
        routes[0].to = middleToken;
        routes[0].stable = isStablePair0;
        routes[0].factory = IPool(pool0).factory();
        routes[1].from = middleToken;
        routes[1].to = outputToken;
        routes[1].stable = isStablePair1;
        routes[1].factory = IPool(pool1).factory();

        uint256[] memory amounts = IRouter(velodromeRouter).swapExactTokensForTokens(
            amountInput,
            amountOutMin,
            routes,
            recipient,
            block.timestamp
        );

        return amounts[2];
    }

}