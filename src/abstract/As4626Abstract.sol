// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./ERC20Permit.sol";
import "./Manageable.sol";
import "./AsTypes.sol";
import "../libs/AsAccounting.sol";

/**
 * @dev Abstract contract containing variables, structs, errors, and events for As4626.
 */
abstract contract As4626Abstract is
    ERC20Permit,
    Manageable,
    Pausable,
    ReentrancyGuard {

    using AsMaths for uint256;

    // Errors
    error LiquidityTooLow(uint256 assets);
    error SelfMintNotAllowed();
    error FeeError();
    error Unauthorized();
    error TransactionExpired();
    error AmountTooHigh(uint256 amount);
    error AmountTooLow(uint256 amount);
    error InsufficientFunds(uint256 amount);
    error WrongToken();
    error AddressZero();

    // Events
    event Deposited(
        address indexed sender,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event Withdrawn(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event SharePriceUpdated(uint256 shareprice, uint256 timestamp);
    event FeesCollected(
        uint256 profit,
        uint256 totalAssets,
        uint256 perfFeesAmount,
        uint256 mgmtFeesAmount,
        uint256 sharesToMint,
        address indexed receiver
    );
    event FeeCollectorUpdated(address indexed feeCollector);
    event FeesUpdated(uint256 perf, uint256 mgmt, uint256 entry, uint256 exit);
    event MaxTotalAssetsSet(uint256 maxTotalAssets);

    // Variables
    ERC20 public underlying;

    Fees internal MAX_FEES;
    uint256 internal constant MAX_UINT256 = type(uint256).max;
    uint256 internal constant ZERO = 0;

    uint256 public minLiquidity;
    uint256 public profitCooldown;
    uint256 public claimableUnderlyingFees;

    uint256 public maxTotalAssets;
    address public feeCollector;
    Fees public fees;
    uint256 public expectedProfits;

    uint256 public lastUpdate;
    Checkpoint public feeCollectedAt;
    uint8 public shareDecimals;
    uint256 public weiPerShare;

    // methods required on StratV5 (specific implementations) + StratAgentV5 (generic implementations)

    /// @return The address of the underlying asset
    function asset() public view returns (address) {
        return address(underlying);
    }

    /// @return The decimals of the share
    function decimals()
        public
        view
        override(ERC20)
        returns (uint8)
    {
        return shareDecimals;
    }

    /// @notice amount of assets in the protocol farmed by the strategy
    /// @dev underlying abstract function to be implemented by the strategy
    /// @return amount of assets in the pool
    function _invested() internal view virtual returns (uint256) {}

    /// @notice amount of assets available and not yet deposited
    /// @return amount of assets available
    function available() public view returns (uint256) {
        return underlying.balanceOf(address(this))
            - claimableUnderlyingFees
            - AsAccounting.unrealizedProfits(
                lastUpdate,
                expectedProfits,
                profitCooldown);
    }

    function invested() public view returns (uint256) {
        return _invested();
    }

    /// @notice Amount of assets under management
    /// @dev We consider each pool as having "debt" to the crate
    /// @return The total amount of assets under management
    function totalAssets() public view returns (uint256) {
        return available() + invested();
    }

    /// @notice The share price equal the amount of assets redeemable for one crate token
    /// @return The virtual price of the crate token
    function sharePrice() public view returns (uint256) {
        uint256 supply = totalSupply();
        return
            supply == 0
                ? weiPerShare
                : totalAssets().mulDiv(weiPerShare, supply);
    }

    /// @notice value of the owner's position in underlying tokens
    /// @param _owner shares owner
    /// @return value of the position in underlying tokens
    function assetsOf(address _owner) public view returns (uint256) {
        return balanceOf(_owner) * sharePrice();
    }

    constructor(
        string[3] memory _erc20Metadata // name, symbol of the share and EIP712 version
    ) ERC20Permit(_erc20Metadata[0], _erc20Metadata[1], _erc20Metadata[2]) {
        _pause();
    }

}
