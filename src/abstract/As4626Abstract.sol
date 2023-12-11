// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./ERC20Permit.sol";
import "./AsManageable.sol";
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
 * @notice All As4626 calls are delegated to the agent (StrategyV5Agent)
 * @dev Make sure all As4626 state variables here to match proxy/implementation slots
 */
abstract contract As4626Abstract is
    ERC20Permit,
    AsManageable,
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
    // event DepositRequest(
    //     address indexed sender,
    //     address indexed operator,
    //     uint256 assets
    // );
    event RedeemRequest(
        address indexed sender,
        address indexed operator,
        address indexed owner,
        uint256 assets
    );
    // event DepositRequestCanceled(address indexed owner, uint256 assets);
    event RedeemRequestCanceled(address indexed owner, uint256 assets);

    // As4626 specific
    event SharePriceUpdate(uint256 shareprice, uint256 timestamp);
    event FeeCollectorUpdate(address indexed feeCollector);
    event FeesUpdate(Fees fees);
    event MaxTotalAssetsSet(uint256 maxTotalAssets);
    // Flash loan
    event FlashLoan(address indexed borrower, uint256 amount, uint256 fee);

    // Errors
    error AmountTooHigh(uint256 amount);
    error AmountTooLow(uint256 amount);
    error AddressZero();
    error WrongRequest(address owner, uint256 amount);
    error FlashLoanDefault(address borrower, uint256 amount);

    // Constants
    uint256 internal constant MAX_UINT256 = type(uint256).max;

    uint16 internal maxSlippageBps = 100; // Strategy default internal ops slippage 1%
    uint256 internal profitCooldown = 10 days; // Profit linearization period (profit locktime)
    uint256 public maxTotalAssets = MAX_UINT256; // Maximum total assets that can be deposited
    uint256 public minLiquidity = 1e7; // Minimum amount to seed liquidity is 1e7 wei (e.g., 10 USDC)

    IERC20Metadata internal underlying; // ERC20 token used as the base denomination
    uint8 internal constant shareDecimals = 8; // Decimals of the share
    uint256 internal constant weiPerShare = 8**10; // weis in a share (base unit)
    Epoch public last; // Epoch tracking latest events

    // Profit-related variables
    uint256 internal expectedProfits; // Expected profits

    Fees internal MAX_FEES = Fees(5_000, 200, 100, 100, 100); // Maximum fees: 50% perf, 2% mgmt, 1% entry, 1% exit, 1% flash
    Fees public fees; // Current fee structure
    address public feeCollector; // Address to collect fees
    uint256 public claimableUnderlyingFees; // Amount of underlying fees (entry+exit) that can be claimed
    mapping(address => bool) public exemptionList; // List of addresses exempted from fees

    Requests internal req;

    // Flash loan
    uint256 internal totalLent;
    uint256 public maxLoan = 1e12; // Maximum amount of flash loan allowed (default to 1e12 eg. 1m usdc)

    /**
     * @param _erc20Metadata ERC20Permit constructor data: name, symbol, EIP712 version
     */
    constructor(
        string[3] memory _erc20Metadata
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
    function decimals() public pure override(ERC20) returns (uint8) {
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
     * @notice Total amount of inputs denominated in underlying
     * @dev Abstract function to be implemented by the strategy
     * @return Amount of assets
     */
    function invested() public view virtual returns (uint256) {}

    /**
     * @notice Amount of assets available to non-requested withdrawals (excluding seed)
     * @return Amount denominated in underlying
     */
    function available() public view returns (uint256) {
        return availableClaimable() - req.totalClaimableUnderlying - minLiquidity;
    }

    /**
     * @notice Total amount of assets available to withdraw
     * @return Amount denominated in underlying
     */
    function availableClaimable() internal view returns (uint256) {
        return
            underlying.balanceOf(address(this)) -
            claimableUnderlyingFees -
            AsAccounting.unrealizedProfits(
                last.harvest,
                expectedProfits,
                profitCooldown
            );
    }

    function availableBorrowable() internal view returns (uint256) {
        return availableClaimable() - totalLent;
    }

    /**
     * @notice Amount of assets under management (including claimable redemptions)
     * @return Amount denominated in underlying
     */
    function totalAssets() public view virtual returns (uint256) {
        return availableClaimable() + invested();
    }

    /**
     * @notice Amount of assets under management used for sharePrice accounting (excluding claimable redemptions)
     * @return Amount denominated in underlying
     */
    function totalAccountedAssets() public view returns (uint256) {
        return totalAssets() - req.totalClaimableUnderlying; // approximated
    }

    /**
     * @notice Amount of shares used for sharePrice accounting (excluding claimable redemptions)
     * @return Amount of shares
     */
    function totalAccountedSupply() public view returns (uint256) {
        return totalSupply() - req.totalClaimableRedemption;
    }

    /**
     * @notice The share price equal to the amount of assets redeemable for one vault token
     * @return The share price
     */
    function sharePrice() public view virtual returns (uint256) {
        uint256 supply = totalAccountedSupply();
        return supply == 0
            ? weiPerShare
            : totalAccountedAssets().mulDiv( // 1e18
                weiPerShare, // 1e8
                supply * ((underlying.decimals() - shareDecimals) ** 10)); // 1e8+(1e18-1e8) = 1e18
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
     * @return Amount of shares you can get for your assets
     */
    function convertToShares(uint256 _assets) public view returns (uint256) {
        return _assets.mulDiv(weiPerShare, sharePrice());
    }

    /**
     * @notice Convert how much asset tokens you can get for your shares
     * @dev Bear in mind that some negative slippage may happen
     * @param _shares Amount of shares to convert
     * @return Amount of asset tokens you can get for your shares
     */
    function convertToAssets(uint256 _shares) public view returns (uint256) {
        return _shares.mulDiv(sharePrice(), weiPerShare);
    }
}
