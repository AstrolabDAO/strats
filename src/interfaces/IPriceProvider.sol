// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

interface IPriceProvider {
  function oracle() external view returns (address);
  function hasFeed(address _asset) external view returns (bool);
  function toUsdBp(address _asset) external view returns (uint256);
  function toUsdBp(address _asset, uint256 _amount) external view returns (uint256);
  function toUsd(address _asset, uint256 _amount) external view returns (uint256);
  function fromUsdBp(address _asset) external view returns (uint256);
  function fromUsdBp(address _asset, uint256 _amount) external view returns (uint256);
  function fromUsd(address _asset, uint256 _amount) external view returns (uint256);
  function exchangeRate(address _base, address _quote) external view returns (uint256);
  function exchangeRateBp(address _base, address _quote) external view returns (uint256);
  function convert(
    address _base,
    uint256 _amount,
    address _quote
  ) external view returns (uint256);
  function setFeed(address _asset, bytes32 _feed, uint256 _validity) external;
  function setFeeds(
    address[] memory _assets,
    bytes32[] memory _feeds,
    uint256[] memory _validities
  ) external;
  function update(bytes calldata _params) external;
}
