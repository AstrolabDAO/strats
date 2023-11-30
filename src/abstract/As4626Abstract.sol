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

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title As4626Abstract - inherited by all strategies
 * @author Astrolab DAO
 * @notice All As4626 calls are delegated to the agent (StrategyAgentV5)
 * @dev Make sure all As4626 state variables here to match proxy/implementation slots
 */
abstract contract As4626Abstract is
    ERC20Permit,
    Manageable,
    Pausable,
    ReentrancyGuard
{
    using AsMaths for uint256;

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
    event DepositRequestCanceled(address indexed owner, uint256 assets);
    event RedeemRequestCanceled(address indexed owner, uint256 assets);

    // As4626 specific
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

    // Constants
    uint256 internal constant MAX_UINT256 = type(uint256).max;
    uint256 internal constant ZERO = 0;
    // State variables for the contract.

    // Base denomination/accounting
    ERC20 public underlying; // ERC20 token used as the base denomination
    Checkpoint public last; // Checkpoint tracking latest events
    uint8 public shareDecimals; // Decimals of the share
    uint256 public weiPerShare; // Conversion rate of wei to shares

    // Limits
    uint256 public maxTotalAssets; // Maximum total assets that can be deposited
    uint256 public minLiquidity = 1e7; // Minimum amount to seed liquidity is 1e7 wei (e.g., 10 USDC)

    // Profit-related variables
    uint256 public expectedProfits; // Expected profits
    uint256 public profitCooldown = 7 days; // Profit linearization period

    // Fees
    Fees internal MAX_FEES = Fees(5_000, 200, 100, 100); // Maximum fees: 50%, 2%, 1%, 1%
    mapping(address => bool) internal exemptionList; // List of addresses exempted from fees
    Fees public fees; // Current fee structure
    address public feeCollector; // Address to collect fees
    uint256 public claimableUnderlyingFees; // Amount of underlying fees that can be claimed

    // ERC7540
    mapping(address => Erc7540Request) internal requestByOperator; // Mapping of ERC7540 requests by operator
    uint256 public redemptionRequestLocktime = 2 days; // Locktime for redemption requests

    uint256 public totalRedemptionRequest; // Total amount requested for redemption
    uint256 public totalUnderlyingRequest; // Total underlying requested
    uint256 public totalDepositRequest; // Total amount requested for deposit

    uint256 public totalClaimableRedemption; // Total amount claimable for redemption
    uint256 public totalClaimableUnderlying; // Total claimable underlying

    /**
     * @param _erc20Metadata ERC20Permit constructor data: name, symbol, version
     */
    constructor(
        string[3] memory _erc20Metadata // name, symbol of the share and EIP712 version
    ) ERC20Permit(_erc20Metadata[0], _erc20Metadata[1], _erc20Metadata[2]) {
        _pause();
    }

    /**
     * @notice Get the address of the underlying asset
     * @return The address of the underlying asset
     */
    function asset() public view returns (address) {
        return address(underlying);
    }

    /**
     * @notice Get the decimals of the share
     * @return The decimals of the share
     */
    function decimals() public view override(ERC20) returns (uint8) {
        return shareDecimals;
    }

    /**
     * @notice Exempt an account from entry/exit fees or remove its exemption
     * @param _account The account to exempt
     * @param _isExempt Whether to exempt or not
     */
    function setExemption(address _account, bool _isExempt) public onlyAdmin {
        exemptionList[_account] = _isExempt;
    }

    /**
     * @notice Amount of assets in the protocol farmed by the strategy
     * @dev Underlying abstract function to be implemented by the strategy
     * @return Amount of assets in the pool
     */
    function _invested() internal view virtual returns (uint256) {}

    /**
     * @notice Amount of assets available and not yet deposited
     * @return Amount of assets available
     */
    function available() public view returns (uint256) {
        return
            underlying.balanceOf(address(this)) -
            claimableUnderlyingFees -
            totalClaimableUnderlying -
            AsAccounting.unrealizedProfits(
                last.harvest,
                expectedProfits,
                profitCooldown
            );
    }

    /**
     * @notice Amount of assets invested by the strategy
     * @return Amount of assets invested
     */
    function invested() public view returns (uint256) {
        return _invested();
    }

    /**
     * @notice Amount of assets under management (excluding claimable redemptions)
     * @return Total amount of assets under management
     */
    function totalAssets() public view virtual returns (uint256) {
        return available() + invested();
    }

    /**
     * @notice The share price equal to the amount of assets redeemable for one crate token
     * @return The virtual price of the crate token
     */
    function sharePrice() public view virtual returns (uint256) {
        uint256 supply = totalSupply() - totalClaimableRedemption;
        return
            supply == 0
                ? weiPerShare
                : totalAssets().mulDiv(weiPerShare, supply);
    }

    /**
     * @notice Value of the owner's position in underlying tokens
     * @param _owner Shares owner
     * @return Value of the position in underlying tokens
     */
    function assetsOf(address _owner) public view returns (uint256) {
        return convertToAssets(balanceOf(_owner));
    }

    /**
     * @notice Convert how many shares you can get for your assets
     * @param _assets Amount of assets to convert
     * @return The amount of shares you can get for your assets
     */
    function convertToShares(uint256 _assets) public view returns (uint256) {
        return _assets.mulDiv(weiPerShare, sharePrice());
    }

    /**
     * @notice Convert how much asset tokens you can get for your shares
     * @dev Bear in mind that some negative slippage may happen
     * @param _shares Amount of shares to convert
     * @return The amount of asset tokens you can get for your shares
     */
    function convertToAssets(uint256 _shares) public view returns (uint256) {
        return _shares.mulDiv(sharePrice(), weiPerShare);
    }

    /**
     * @notice Get the pending redeem request for a specific operator
     * @param operator The operator's address
     * @return The amount of shares pending redemption
     */
    function pendingRedeemRequest(
        address operator
    ) external view returns (uint256) {
        return requestByOperator[operator].shares;
    }

    /**
     * @notice Check if a redemption request is claimable
     * @param requestTimestamp The timestamp of the redemption request
     * @return Whether the redemption request is claimable
     */
    function isRequestClaimable(
        uint256 requestTimestamp
    ) public view returns (bool) {
        return
            requestTimestamp <
            AsMaths.max(
                block.timestamp - redemptionRequestLocktime,
                last.liquidate
            );
    }

    /**
     * @notice Get the maximum claimable redemption amount
     * @return The maximum claimable redemption amount
     */
    function maxClaimableUnderlying() public view returns (uint256) {
        return
            AsMaths.min(
                totalUnderlyingRequest,
                underlying.balanceOf(address(this)) -
                    claimableUnderlyingFees -
                    AsAccounting.unrealizedProfits(
                        last.harvest,
                        expectedProfits,
                        profitCooldown
                    )
            );
    }

    /**
     * @notice Get the maximum redemption claim for a specific owner
     * @param _owner The owner's address
     * @return The maximum redemption claim for the owner
     */
    function maxRedemptionClaim(address _owner) public view returns (uint256) {
        Erc7540Request memory request = requestByOperator[_owner];
        return
            isRequestClaimable(request.timestamp)
                ? AsMaths.min(request.shares, totalClaimableRedemption)
                : 0;
    }
}
