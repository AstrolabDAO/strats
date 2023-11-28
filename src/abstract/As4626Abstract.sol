// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
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
    error WrongRequest(address owner, uint256 amount);

    // Events
    // ERC4626
    event Deposit(
        address indexed sender,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    // ERC7540
    event DepositRequest(
        address indexed sender,
        address indexed operator,
        uint256 assets
    );
    event RedeemRequest(
        address indexed sender,
        address indexed operator,
        address indexed owner,
        uint256 assets
    );
    event DepositRequestCanceled(
        address indexed owner,
        uint256 assets
    );
    event RedeemRequestCanceled(
        address indexed owner,
        uint256 assets
    );
    // custom
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

    Fees internal MAX_FEES = Fees(5_000, 200, 100, 100); // 50%, 2%, 1%, 1%
    uint256 internal constant MAX_UINT256 = type(uint256).max;
    uint256 internal constant ZERO = 0;
    mapping(address => bool) internal exemptionList;

    // ERC7540
    mapping(address => Erc7540Request) internal requestByOperator;
    Erc7540Request[] internal requests;

    uint256 public totalClaimableRedemption;
    uint256 public totalRedemptionRequest;
    uint256 public totalDepositRequest;

    // custom
    uint256 public minLiquidity;
    uint256 public profitCooldown = 7 days; // profit linearization period
    uint256 public redemptionRequestLocktime = 2 days;
    uint256 public claimableUnderlyingFees;

    uint256 public maxTotalAssets;
    address public feeCollector;
    Fees public fees;
    uint256 public expectedProfits;

    Checkpoint public last;
    uint8 public shareDecimals;
    uint256 public weiPerShare;

    constructor(
        string[3] memory _erc20Metadata // name, symbol of the share and EIP712 version
    ) ERC20Permit(_erc20Metadata[0], _erc20Metadata[1], _erc20Metadata[2]) {
        _pause();
    }

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

    /// @notice Exempt an account from entry/exit fees or remove its exemption
    /// @param _account The account to exempt
    /// @param _isExempt Whether to exempt or not
    function setExemption(address _account, bool _isExempt) public onlyAdmin {
        exemptionList[_account] = _isExempt;
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
            - convertToAssets(totalClaimableRedemption)
            - AsAccounting.unrealizedProfits(
                last.harvest,
                expectedProfits,
                profitCooldown);
    }

    function invested() public view returns (uint256) {
        return _invested();
    }

    /// @notice Amount of assets under management (excluding claimable redemptions)
    /// @dev We consider each pool as having "debt" to the crate
    /// @return The total amount of assets under management
    function totalAssets() public view virtual returns (uint256) {
        return available() + invested();
    }

    /// @notice The share price equal the amount of assets redeemable for one crate token
    /// @return The virtual price of the crate token
    function sharePrice() public view virtual returns (uint256) {
        // exclude claimable redemptions from the total supply
        uint256 supply = (totalSupply() - totalClaimableRedemption);
        return
            supply == 0 // supply will never be zero after initialization
                ? weiPerShare
                : totalAssets().mulDiv(weiPerShare, supply);
    }

    /// @notice value of the owner's position in underlying tokens
    /// @param _owner shares owner
    /// @return value of the position in underlying tokens
    function assetsOf(address _owner) public view returns (uint256) {
        return balanceOf(_owner) * sharePrice();
    }

    /// @notice Convert how much shares you can get for your assets
    /// @param _assets Amount of assets to convert
    /// @return The amount of shares you can get for your assets
    function convertToShares(uint256 _assets) public view returns (uint256) {
        return _assets.mulDiv(weiPerShare, sharePrice());
    }

    /// @notice Convert how much asset tokens you can get for your shares
    /// @dev Bear in mind that some negative slippage may happen
    /// @param _shares amount of shares to covert
    /// @return The amount of asset tokens you can get for your shares
    function convertToAssets(uint256 _shares) public view returns (uint256) {
        return _shares.mulDiv(sharePrice(), weiPerShare);
    }
}
