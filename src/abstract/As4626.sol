// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./As4626Abstract.sol";
import "./AsTypes.sol";
import "../libs/AsMaths.sol";
import "../libs/AsAccounting.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title As4626 Abstract - inherited by all strategies
 * @author Astrolab DAO
 * @notice All As4626 calls are delegated to the agent (StrategyAgentV5)
 * @dev Make sure all state variables are in As4626Abstract to match proxy/implementation slots
 */
abstract contract As4626 is As4626Abstract {
    using AsMaths for uint256;
    using AsMaths for int256;
    using SafeERC20 for ERC20;

    /**
     * @dev Initialize the contract after deployment.
     * @param _fees Fee structure for the contract
     * @param _underlying Address of the underlying ERC20 token
     * @param _feeCollector Address where fees will be collected
     */
    function init(
        Fees memory _fees,
        address _underlying,
        address _feeCollector
    ) public virtual onlyAdmin {
        // check that the fees are not too high
        if (!AsAccounting.checkFees(_fees, MAX_FEES)) revert FeeError();
        fees = _fees;
        underlying = ERC20(_underlying);
        feeCollector = _feeCollector;

        // use the same decimals as the underlying
        shareDecimals = ERC20(_underlying).decimals();
        weiPerShare = 10 ** shareDecimals;
        last.accountedSharePrice = weiPerShare;
    }

    /**
     * @notice Mints shares to the receiver by depositing underlying tokens
     * @param _shares Amount of shares minted to the _receiver
     * @param _receiver Shares receiver
     * @return assets Amount of assets deposited
     */
    function mint(
        uint256 _shares,
        address _receiver
    ) public nonReentrant returns (uint256 assets) {
        assets = convertToAssets(_shares);

        if (assets == 0 || _shares == 0) revert AmountTooLow(0);
        if (totalAssets() < minLiquidity) revert LiquidityTooLow(totalAssets());
        if (assets > maxDeposit(_receiver))
            revert AmountTooHigh(maxDeposit(_receiver));
        if (_receiver == address(this)) revert SelfMintNotAllowed();

        // Moving value
        underlying.safeTransferFrom(msg.sender, address(this), assets);
        _mint(_receiver, _shares);
        emit Deposit(msg.sender, _receiver, assets, _shares);
    }

    /**
     * @notice Mints shares to the receiver by depositing underlying tokens
     * @dev Pausing the contract should prevent depositing by setting maxDepositAmount to 0
     * @param _amount Amount of underlying tokens to deposit
     * @param _receiver Address that will get the shares
     * @param _minShareAmount Minimum amount of shares to be minted, like slippage on Uniswap
     * @return shares Amount of shares minted to the _receiver
     */
    function _deposit(
        uint256 _amount,
        address _receiver,
        uint256 _minShareAmount
    ) internal nonReentrant returns (uint256 shares) {
        if (_receiver == address(this)) revert SelfMintNotAllowed();
        if (_amount == 0) revert AmountTooLow(0);
        if (_amount > maxDeposit(address(0)))
            // maxDeposit(address(0) is maxDeposit for anyone
            revert AmountTooHigh(maxDeposit(_receiver));

        // save totalAssets before transferring
        uint256 assetsAvailable = totalAssets();
        // Moving value
        underlying.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 supply = totalSupply();

        // slice the fee from the amount (gas optimized)
        if (!exemptionList[_receiver]) {
            uint256 fee = _amount.bp(fees.entry);
            claimableUnderlyingFees += fee;
            _amount -= fee;
        }

        shares = supply == 0
            ? _amount.mulDiv(sharePrice(), weiPerShare)
            : _amount.mulDiv(supply, assetsAvailable);

        if (shares == 0 || shares < _minShareAmount)
            revert AmountTooLow(shares);

        // mint shares
        _mint(_receiver, shares);
        emit Deposit(msg.sender, _receiver, _amount, shares);
    }

    /**
     * @notice Previews the amount of shares that will be minted for a given deposit amount
     * @param _amount Amount of underlying tokens to deposit
     * @return shares Amount of shares that will be minted
     */
    function previewDeposit(
        uint256 _amount
    ) public view returns (uint256 shares) {
        return convertToShares(_amount.subBp(fees.entry));
    }

    /**
     * @notice Mints shares to the receiver by depositing underlying tokens
     * @dev Beware, there's no slippage control - use safeDeposit if you want it
     * @param _amount Amount of underlying tokens to deposit
     * @param _receiver Address that will get the shares
     * @return shares Amount of shares minted to the _receiver
     */
    function deposit(
        uint256 _amount,
        address _receiver
    ) public returns (uint256 shares) {
        return _deposit(_amount, _receiver, 0);
    }

    /**
     * @notice Mints shares to the receiver by depositing underlying tokens
     * @dev Overloaded version with slippage control
     * @param _amount Amount of underlying tokens to deposit
     * @param _receiver Address that will get the shares
     * @param _minShareAmount Minimum amount of shares to be minted, like slippage on Uniswap
     * @return shares Amount of shares minted to the _receiver
     */
    function safeDeposit(
        uint256 _amount,
        address _receiver,
        uint256 _minShareAmount
    ) public returns (uint256 shares) {
        return _deposit(_amount, _receiver, _minShareAmount);
    }

    /**
     * @notice The vault takes a small fee to prevent share price updates arbitrages
     * @dev Fees should already have been taken into account
     * @param _amount Amount of assets to pull from the crate
     * @param _shares Amount of shares to burn
     * @param _minAmountOut The minimum amount of assets we'll accept
     * @param _receiver Who will get the withdrawn assets
     * @param _owner Whose shares we'll burn
     * @return assets Amount of assets withdrawn
     */
    function _withdraw(
        uint256 _amount,
        uint256 _shares,
        uint256 _minAmountOut,
        address _receiver,
        address _owner
    ) internal nonReentrant whenNotPaused returns (uint256) {
        if (_amount == 0 || _shares == 0) revert AmountTooLow(0);
        if (_shares >= totalSupply()) _shares = totalSupply() - 1; // never redeem all shares

        // spend the allowance if the msg.sender isn't the receiver
        if (msg.sender != _owner) {
            _spendAllowance(_owner, msg.sender, _shares);
        }

        uint256 claimable = 0;
        Erc7540Request memory request = requestByOperator[_receiver];

        if (
            totalClaimableRedemption > 0 &&
            isRequestClaimable(request.timestamp)
        ) {
            claimable = AsMaths.min(request.shares, totalClaimableRedemption);
        }

        uint256 price = sharePrice();

        if (claimable >= _shares) {
            // positive slippage (request.sharePrice - price > 0)
            price = AsMaths.min(price, request.sharePrice);
        }

        // expected - recovered == strategy profit (exit fee + slippage)
        (uint256 expected, uint256 recovered) = (
            _shares.mulDiv(request.sharePrice, weiPerShare),
            _shares.mulDiv(price, weiPerShare)
        );

        // the request claim cannot be partial: the receiver either claim all shares from its pending request or none
        if (claimable >= _shares) {
            request.shares -= _shares;

            totalRedemptionRequest -= _shares;
            totalUnderlyingRequest -= AsMaths.min(
                expected,
                totalUnderlyingRequest
            );

            totalClaimableRedemption -= _shares;
            totalClaimableUnderlying -= AsMaths.min(
                recovered,
                totalClaimableUnderlying
            );
        }

        // slice fee from burnt shares if not exempted
        if (!exemptionList[_owner]) {
            uint256 fee = _shares.bp(fees.exit);
            recovered -= fee.mulDiv(price, weiPerShare);
            _transfer(_owner, address(this), fee);
            _shares -= fee;
        }

        // check slippage
        if (recovered <= _minAmountOut) revert AmountTooLow(recovered);

        // burn the shares (reverts if the owner doesn't have enough)
        _burn(_owner, _shares);
        underlying.safeTransfer(_receiver, recovered);
        emit Withdraw(msg.sender, _receiver, _owner, recovered, _shares);
        return recovered;
    }

    /**
     * @notice Withdraw assets denominated in underlying
     * @dev Beware, there's no slippage control - use safeWithdraw if you want it
     * @param _amount Amount of underlying tokens to withdraw
     * @param _receiver Who will get the withdrawn assets
     * @param _owner Whose shares we'll burn
     * @return shares Amount of shares burned
     */
    function withdraw(
        uint256 _amount,
        address _receiver,
        address _owner
    ) external virtual returns (uint256 shares) {
        // This represents the amount of shares that we're about to burn
        shares = convertToShares(_amount);
        return _withdraw(_amount, shares, 0, _receiver, _owner);
    }

    /**
     * @notice Withdraw assets denominated in underlying
     * @dev Overloaded version with slippage control
     * @param _amount Amount of underlying tokens to withdraw
     * @param _minAmount The minimum amount of assets we'll accept
     * @param _receiver Who will get the withdrawn assets
     * @param _owner Whose shares we'll burn
     * @return shares Amount of shares burned
     */
    function safeWithdraw(
        uint256 _amount,
        uint256 _minAmount,
        address _receiver,
        address _owner
    ) public virtual returns (uint256 shares) {
        // This represents the amount of shares that we're about to burn
        shares = convertToShares(_amount); // take fees here
        _withdraw(_amount, shares, _minAmount, _receiver, _owner);
    }

    /**
     * @notice Redeem shares for their underlying value
     * @dev Beware, there's no slippage control - you need to use the overloaded function if you want it
     * @param _shares Amount of shares to redeem
     * @param _receiver Who will get the withdrawn assets
     * @param _owner Whose shares we'll burn
     * @return assets Amount of assets withdrawn
     */
    function redeem(
        uint256 _shares,
        address _receiver,
        address _owner
    ) external returns (uint256 assets) {
        return (
            _withdraw(
                convertToAssets(_shares), // take fees
                _shares,
                0,
                _receiver,
                _owner
            )
        );
    }

    /**
     * @dev Overloaded version with slippage control
     * @param _shares Amount of shares to redeem
     * @param _minAmountOut The minimum amount of assets accepted
     * @param _receiver Who will get the withdrawn assets
     * @param _owner Whose shares we'll burn
     * @return assets Amount of assets withdrawn
     */
    function safeRedeem(
        uint256 _shares,
        uint256 _minAmountOut,
        address _receiver,
        address _owner
    ) external returns (uint256 assets) {
        return (
            _withdraw(
                convertToAssets(_shares),
                _shares, // _shares
                _minAmountOut,
                _receiver, // _receiver
                _owner // _owner
            )
        );
    }

    /**
     * @notice Trigger a fee collection: mints shares to the feeCollector
     * @dev This function can be called by any keeper
     */
    function collectFees() external onlyKeeper {
        (
            uint256 perfFeesAmount,
            uint256 mgmtFeesAmount,
            uint256 profit
        ) = AsAccounting.computeFees(totalAssets(), sharePrice(), fees, last);

        if (feeCollector == address(0)) revert AddressZero();
        if (profit == 0) return;

        uint256 outstandingFees = perfFeesAmount +
            mgmtFeesAmount +
            claimableUnderlyingFees;
        uint256 sharesToMint = convertToShares(outstandingFees);

        _mint(feeCollector, sharesToMint);
        claimableUnderlyingFees = 0;

        last.feeCollection = block.timestamp;
        last.accountedSharePrice = sharePrice();

        emit FeesCollected(
            profit,
            totalAssets(),
            perfFeesAmount,
            mgmtFeesAmount,
            sharesToMint,
            feeCollector
        );
    }

    /**
     * @notice Pause the crate
     */
    function pause() external onlyManager {
        _pause();
        // This prevents deposit
        maxTotalAssets = 0;
    }

    /**
     * @notice Unpause the crate
     */
    function unpause() external onlyManager {
        _unpause();
    }

    /**
     * @notice Update Fee Recipient address
     * @param _feeCollector The new address for fee collection
     */
    function setFeeCollector(address _feeCollector) external onlyAdmin {
        if (_feeCollector == address(0)) revert AddressZero();
        feeCollector = _feeCollector;
        emit FeeCollectorUpdated(feeCollector);
    }

    /**
     * @notice Set the max amount of total assets that can be deposited
     * @param _maxTotalAssets The maximum amount of assets
     */
    function setMaxTotalAssets(uint256 _maxTotalAssets) public onlyAdmin {
        maxTotalAssets = _maxTotalAssets;
        emit MaxTotalAssetsSet(_maxTotalAssets);
    }

    /**
     * @notice Set maxTotalAssets + deposits seed liquidity into the vault
     * @dev Deposits are disabled when the assets reach this limit
     * @param _seedDeposit amount of assets to seed the vault
     * @param _maxTotalAssets max amount of assets
     */
    function seedLiquidity(
        uint256 _seedDeposit,
        uint256 _maxTotalAssets
    ) external onlyManager {
        // 1e8 is the minimum amount of assets required to seed the vault (1 USDC or .1Gwei ETH)
        // allowance should be given to the vault before calling this function
        if (_seedDeposit < (minLiquidity - totalAssets()))
            revert AmountTooLow(_seedDeposit);

        // seed the vault with some assets if it's empty
        setMaxTotalAssets(_maxTotalAssets);

        if (totalSupply() < minLiquidity) {
            _deposit(_seedDeposit, msg.sender, 1);
        }
        _unpause();
    }

    /**
     * @notice Set the fees if compliant with MAX_FEES constant
     * @dev Maximum fees are registered as constants
     * @param _fees.perf Fee on performance
     */
    function setFees(Fees memory _fees) external onlyAdmin {
        if (!AsAccounting.checkFees(_fees, MAX_FEES)) revert FeeError();
        fees = _fees;
        emit FeesUpdated(fees.perf, fees.mgmt, fees.entry, fees.exit);
    }

    /**
     * @notice Set the minimum amount of assets to seed the vault
     * @dev This is to avoid dust amounts of assets
     * @param _minLiquidity The minimum amount of assets to seed the vault
     */
    function setMinLiquidity(uint256 _minLiquidity) external onlyAdmin {
        minLiquidity = _minLiquidity;
    }

    /**
     * @notice Set the cooldown period for realizing profits
     * @dev This is to avoid MEV/arbs
     * @param _profitCooldown The cooldown period for realizing profits
     */
    function setProfitCooldown(uint256 _profitCooldown) external onlyAdmin {
        profitCooldown = _profitCooldown;
    }

    function setRedemptionRequestLocktime(
        uint256 _redemptionRequestLocktime
    ) external onlyAdmin {
        redemptionRequestLocktime = _redemptionRequestLocktime;
    }

    /**
     * @notice Preview how much asset tokens the caller has to pay to acquire x shares
     * @param _shares Amount of shares that we acquire
     * @return shares Amount of asset tokens that the caller should pay
     */
    function previewMint(uint256 _shares) public view returns (uint256) {
        return convertToAssets(_shares);
    }

    /**
     * @notice Preview how many shares the caller needs to burn to get his assets back
     * @dev You may get less asset tokens than you expect due to slippage
     * @param _assets How much we want to get
     * @return How many shares will be burnt
     */
    function previewWithdraw(uint256 _assets) public view returns (uint256) {
        return convertToShares(_assets.subBp(fees.exit));
    }

    /**
     * @notice Preview how many underlying tokens the caller will get for burning his _shares
     * @param _shares Amount of shares that we burn
     * @return Preview amount of underlying tokens that the caller will get for his shares
     */
    function previewRedeem(uint256 _shares) public view returns (uint256) {
        uint256 afterFees = convertToAssets(_shares).subBp(fees.exit);
        uint256 claimable = AsMaths.min(
            requestByOperator[msg.sender].shares,
            totalClaimableRedemption
        );
        return AsMaths.max(available(), claimable) >= afterFees ? afterFees : 0;
    }

    /**
     * @return The maximum amount of assets that can be deposited
     */
    function maxDeposit(address) public view returns (uint256) {
        uint256 _totalAssets = totalAssets();
        return
            _totalAssets > maxTotalAssets ? 0 : maxTotalAssets - _totalAssets;
    }

    /**
     * @return The maximum amount of shares that can be minted
     */
    function maxMint(address) public view returns (uint256) {
        return convertToShares(maxDeposit(address(0)));
    }

    /**
     * @return The maximum amount of assets that can be withdrawn
     */
    function maxWithdraw(address _owner) public view returns (uint256) {
        return convertToAssets(maxRedeem(_owner));
    }

    /**
     * @return The maximum amount of shares that can be redeemed by the owner in a single transaction
     */
    function maxRedeem(address _owner) public view returns (uint256) {
        return
            paused() ? 0 : AsMaths.max(maxRedemptionClaim(_owner), available());
    }

    /**
     * @notice Initiate a deposit request for assets denominated in underlying
     * @param assets Amount of underlying tokens to deposit
     * @param operator Address initiating the request
     */
    function requestDeposit(
        uint256 assets,
        address operator
    ) external virtual {}

    /**
     * @notice Initiate a redeem request for shares
     * @param shares Amount of shares to redeem
     * @param operator Address initiating the request
     * @param owner The owner of the shares to be redeemed
     */
    function requestRedeem(
        uint256 shares,
        address operator,
        address owner
    ) public nonReentrant {
        if (owner != msg.sender) revert WrongRequest(msg.sender, shares);
        if (shares == 0) revert AmountTooLow(shares);
        if (balanceOf(owner) < shares) revert InsufficientFunds(shares);
        Erc7540Request storage request = requestByOperator[operator];
        uint256 price = sharePrice();

        // if a request is already pending, only accept increase requests
        if (request.shares > 0) {
            if (request.shares < shares) revert WrongRequest(owner, shares);

            // temporary clear the request
            totalRedemptionRequest -= request.shares;
            totalUnderlyingRequest -= AsMaths.min(
                request.shares.mulDiv(request.sharePrice, weiPerShare),
                totalUnderlyingRequest
            );

            // volume weighted average price for the request
            uint256 increase = request.shares - shares;

            // the new request sharePrice is the two requests vwap (can overflow for extreme values when weiPerShare == 1e18)
            request.sharePrice =
                ((price * increase) + (request.sharePrice * request.shares)) /
                shares;
        } else {
            request.sharePrice = price;
        }

        request.shares = shares;

        // throttle the request to avoid claimable overdraft
        request.timestamp = block.timestamp;
        totalRedemptionRequest += shares;
        totalUnderlyingRequest += request.sharePrice.mulDiv(
            request.shares,
            weiPerShare
        );

        emit RedeemRequest(owner, operator, owner, shares);
    }

    /**
     * @notice Initiate a withdraw request for assets denominated in underlying
     * @param _amount Amount of underlying tokens to withdraw
     * @param operator Address initiating the request
     * @param owner The owner of the shares to be redeemed
     */
    function requestWithdraw(
        uint256 _amount,
        address operator,
        address owner
    ) external {
        return requestRedeem(convertToShares(_amount), operator, owner);
    }

    /**
     * @notice Cancel a deposit request
     * @param operator Address initiating the request
     * @param owner The owner of the shares to be redeemed
     */
    function cancelDepositRequest(
        address operator,
        address owner
    ) external virtual {}

    /**
     * @notice Cancel a redeem request
     * @param operator Address initiating the request
     * @param owner The owner of the shares to be redeemed
     */
    function cancelRedeemRequest(address operator, address owner) external {
        require(
            owner == msg.sender || operator == msg.sender,
            "Caller is not owner or operator"
        );

        Erc7540Request storage request = requestByOperator[operator];
        uint256 amount = request.shares;
        uint256 price = sharePrice();

        if (price > request.sharePrice) {
            // burn the excess shares from the loss incurred while not farming
            // with the idle funds (opportunity cost)
            uint256 opportunityCost = amount.mulDiv(
                price - request.sharePrice,
                weiPerShare
            );
            _burn(owner, opportunityCost);
        }

        totalRedemptionRequest -= amount;
        request.shares = 0;

        emit RedeemRequestCanceled(owner, amount);
    }

    receive() external payable {}
}
