interface IVelodromeTwap {

    struct Observation {
        uint256 timestamp;
        uint256 reserve0Cumulative;
        uint256 reserve1Cumulative;
    }

    function observationLength() external view returns (uint256);

    function observations(uint index) external view returns (Observation memory observation);

    function stable() external view returns (bool);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves() external view returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast);

    function blockTimestampLast() external view returns (uint256);

    function reserve0CumulativeLast() external view returns (uint256);

    function reserve1CumulativeLast() external view returns (uint256);
}