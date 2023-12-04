// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAs4626 {
    function sharePrice() external view returns (uint256);
    function decimals() external view returns (uint256);
    function underlying() external view returns (address);
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function invested() external view returns (uint256);
    function availbalance() external view returns (uint256);
    function totalAccountedAssets() external view returns (uint256);
    function totalAccountedSupply() external view returns (uint256);
}
