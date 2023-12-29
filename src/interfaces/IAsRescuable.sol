// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.0;

interface IAsRescuable {
    function requestRescue(address _token) external;
    function rescue(address _token) external;
}
