// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./ERC20.sol";
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
    ERC20,
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
    event RedeemRequest(
        address indexed sender,
        address indexed operator,
        address indexed owner,
        uint256 assets
    );
    // event DepositRequestCanceled(address indexed owner, uint256 assets);
    event RedeemRequestCanceled(address indexed owner, uint256 assets);

    // As4626 specific
    // Flash loan
    event FlashLoan(address indexed borrower, uint256 amount, uint256 fee);

    // Errors
    error AmountTooHigh(uint256 amount);
    error AmountTooLow(uint256 amount);
    error AddressZero();
    error FlashLoanDefault(address borrower, uint256 amount);

    // Constants
    uint256 internal constant MAX_UINT256 = type(uint256).max;

    uint256 internal profitCooldown = 10 days; // Profit linearization period (profit locktime)
    uint256 public maxTotalAssets = MAX_UINT256; // Maximum total assets that can be deposited
    uint256 public minLiquidity = 1e7; // Minimum amount to seed liquidity is 1e7 wei (e.g., 10 USDC)
    uint16 internal maxSlippageBps = 100; // Strategy default internal ops slippage 1%

    IERC20Metadata public asset; // ERC20 token used as the base denomination
    uint8 internal assetDecimals; // ERC20 token decimals
    uint256 internal constant weiPerShare = 1e8; // weis in a share (base unit)
    uint256 internal weiPerAsset; // weis in an asset (underlying unit)
    Epoch public last; // Epoch tracking latest events

    // Profit-related variables
    uint256 internal expectedProfits; // Expected profits

    Fees public fees; // Current fee structure
    address public feeCollector; // Address to collect fees
    uint256 public claimableAssetFees; // Amount of asset fees (entry+exit) that can be claimed
    mapping(address => bool) public exemptionList; // List of addresses exempted from fees

    Requests internal req;

    // Flash loan
    uint256 internal totalLent;
    uint256 public maxLoan = 1e12; // Maximum amount of flash loan allowed (default to 1e12 eg. 1m usdc)

    constructor() {
        _pause();
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
     * @notice Total amount of inputs denominated in asset
     * @dev Abstract function to be implemented by the strategy
     * @return Amount of assets
     */
    function invested() public view virtual returns (uint256) {}

    /**
     * @notice Amount of assets available to non-requested withdrawals (excluding seed)
     * @return Amount denominated in asset
     */
    function available() public view returns (uint256) {
        return availableBorrowable().subMax0(
            convertToAssets(req.totalClaimableRedemption));
    }

    /**
     * @notice Total amount of assets available to withdraw
     * @return Amount denominated in asset
     */
    function availableClaimable() internal view returns (uint256) {
        return
            asset.balanceOf(address(this)) -
            claimableAssetFees -
            AsAccounting.unrealizedProfits(
                last.harvest,
                expectedProfits,
                profitCooldown
            );
    }

    /**
     * @dev Calculates the amount of borrowable assets that are currently available
     * @return The amount of borrowable assets
     */
    function availableBorrowable() internal view returns (uint256) {
        return availableClaimable() - totalLent;
    }

    /**
     * @notice Amount of assets under management (including claimable redemptions)
     * @return Amount denominated in asset
     */
    function totalAssets() public view virtual returns (uint256) {
        return availableClaimable() + invested();
    }

    /**
     * @notice Amount of assets under management used for sharePrice accounting (excluding claimable redemptions approximated with previous accounted sharePrice)
     * @return Amount denominated in asset
     */
    function totalAccountedAssets() public view returns (uint256) {
        return totalAssets() - req.totalClaimableRedemption.mulDiv(last.sharePrice * weiPerAsset, weiPerShare ** 2); // eg. (1e8+1e8+1e6)-(1e8+1e8) = 1e6
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
            : totalAccountedAssets().mulDiv( // eg. e6
                weiPerShare ** 2, // 1e8*2
                supply * weiPerAsset); // eg. (1e6+1e8+1e8)-(1e8+1e6)
    }

    /**
     * @notice Value of the owner's position in asset tokens
     * @param _owner Shares owner
     * @return Value of the position in asset tokens
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
        return _assets.mulDiv(weiPerShare ** 2, sharePrice() * weiPerAsset); // eg. 1e6+(1e8+1e8)-(1e8+1e6) = 1e8
    }

    /**
     * @notice Convert how much asset tokens you can get for your shares
     * @dev Bear in mind that some negative slippage may happen
     * @param _shares Amount of shares to convert
     * @return Amount of asset tokens you can get for your shares
     */
    function convertToAssets(uint256 _shares) public view returns (uint256) {
        return _shares.mulDiv(sharePrice() * weiPerAsset, weiPerShare ** 2); // eg. 1e8+(1e8+1e6)-(1e8+1e8) = 1e6
    }
}
