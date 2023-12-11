// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.0;

import "./As4626Abstract.sol";
import "./AsTypes.sol";
import "../interfaces/IAs4626.sol";
import "../libs/SafeERC20.sol";
import "../libs/AsMaths.sol";
import "../libs/AsAccounting.sol";
import "./AsRescuable.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title As4626 Abstract - inherited by all strategies
 * @author Astrolab DAO
 * @notice All As4626 calls are delegated to the agent (StrategyV5Agent)
 * @dev Make sure all state variables are in As4626Abstract to match proxy/implementation slots
 */
abstract contract As4626 is As4626Abstract {
    using AsMaths for uint256;
    using AsMaths for int256;
    using SafeERC20 for IERC20Metadata;

    receive() external payable {}

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
        if (!AsAccounting.checkFees(_fees, MAX_FEES)) revert Unauthorized();
        fees = _fees;
        feeCollector = _feeCollector;

        underlying = IERC20Metadata(_underlying);
        last.accountedSharePrice = weiPerShare;
        last.accountedProfit = weiPerShare;
        last.feeCollection = uint64(block.timestamp);
        last.liquidate = uint64(block.timestamp);
        last.harvest = uint64(block.timestamp);
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
        uint256 price = sharePrice();
        assets = _shares.mulDiv(price, weiPerShare);

        if (assets == 0 || _shares == 0) revert AmountTooLow(0);
        if (_receiver == address(this) || totalAssets() < minLiquidity)
            revert Unauthorized();
        if (assets > maxDeposit(_receiver))
            revert AmountTooHigh(maxDeposit(_receiver));

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
        if (_receiver == address(this)) revert Unauthorized();
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
            uint256 feeAmount = _amount.bp(fees.entry);
            claimableUnderlyingFees += feeAmount;
            _amount -= feeAmount;
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
     * @dev Unlike safeDeposit, there's no slippage control here
     * @param _amount Amount of underlying tokens to deposit
     * @param _receiver Address that will get the shares
     * @return shares Amount of shares minted to the _receiver
     */
    function deposit(
        uint256 _amount,
        address _receiver
    ) public whenNotPaused returns (uint256 shares) {
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
    ) public whenNotPaused returns (uint256 shares) {
        return _deposit(_amount, _receiver, _minShareAmount);
    }

    /**
     * @notice Withdraw assets denominated in underlying
     * @dev Unlike safeWithdraw, there's no slippage control here
     * @param _amount Amount of underlying tokens to withdraw
     * @param _receiver Who will get the withdrawn assets
     * @param _owner Whose shares we'll burn
     * @return shares Amount of shares burned
     */
    function _withdraw(
        uint256 _amount,
        uint256 _shares,
        uint256 _minAmountOut,
        address _receiver,
        address _owner
    ) internal nonReentrant returns (uint256) {
        if (_amount == 0 || _shares == 0) revert AmountTooLow(0);

        uint256 price = sharePrice();
        if (_shares >= (totalSupply() - convertToShares(minLiquidity)))
            revert Unauthorized();

        if (msg.sender != _owner) {
            _spendAllowance(_owner, msg.sender, _shares);
        }

        Erc7540Request storage request = req.byOperator[_receiver];
        uint256 claimable = (req.totalClaimableRedemption > 0 &&
            isRequestClaimable(request.timestamp))
            ? AsMaths.min(request.shares, req.totalClaimableRedemption)
            : 0;

        price = (claimable >= _shares)
            ? AsMaths.min(price, request.sharePrice)
            : price;
        uint256 recovered = _shares.mulDiv(price, weiPerShare);

        if (claimable >= _shares) {
            req.byOperator[_receiver].shares -= _shares;
            req.totalRedemption -= AsMaths.min(_shares, req.totalRedemption);
            req.totalUnderlying -= AsMaths.min(
                _shares.mulDiv(request.sharePrice, weiPerShare),
                req.totalUnderlying
            );
            req.totalClaimableRedemption -= AsMaths.min(
                _shares,
                req.totalClaimableRedemption
            );
            req.totalClaimableUnderlying -= AsMaths.min(
                recovered,
                req.totalClaimableUnderlying
            );
        }

        if (!exemptionList[_owner]) {
            uint256 fee = _shares.bp(fees.exit);
            recovered -= fee.mulDiv(price, weiPerShare);
            _transfer(_owner, address(this), fee);
            _shares -= fee;
        }

        if (recovered <= _minAmountOut) revert AmountTooLow(recovered);

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
    ) external whenNotPaused returns (uint256 shares) {
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
    ) public whenNotPaused returns (uint256 shares) {
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
    function collectFees() external nonReentrant onlyKeeper {
        (
            uint256 assets,
            uint256 price,
            uint256 profit,
            uint256 toMint
        ) = AsAccounting.collectFees(IAs4626(address(this)));
        _mint(feeCollector, toMint);
        last.feeCollection = uint64(block.timestamp);
        last.accountedTotalAssets = assets;
        last.accountedSharePrice = price;
        last.accountedProfit = profit;
        last.accountedTotalSupply = totalSupply();
        claimableUnderlyingFees = 0;
    }

    /**
     * @notice Pause the vault
     */
    function pause() external onlyManager {
        _pause();
        maxTotalAssets = 0; // This prevents deposit
    }

    /**
     * @notice Unpause the vault
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
        emit FeeCollectorUpdate(feeCollector);
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
        // if the vault is still paused, unpause it
        if (paused()) _unpause();
    }

    /**
     * @notice Set the fees if compliant with MAX_FEES constant
     * @dev Maximum fees are registered as constants
     * @param _fees.perf Fee on performance
     */
    function setFees(Fees memory _fees) external onlyAdmin {
        if (!AsAccounting.checkFees(_fees, MAX_FEES)) revert Unauthorized();
        fees = _fees;
        emit FeesUpdate(_fees);
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
     * @dev Helps avoid MEV/arbs on the sharePrice
     * @param _profitCooldown The cooldown period for realizing profits
     */
    function setProfitCooldown(uint256 _profitCooldown) external onlyAdmin {
        profitCooldown = _profitCooldown;
    }

    /**
     * @notice Set the redemption request locktime
     * @dev Helps avoid MEV/arbs on the vault liquidity
     * @param _redemptionLocktime The redemption request locktime
     */
    function setRedemptionRequestLocktime(
        uint256 _redemptionLocktime
    ) external onlyAdmin {
        req.redemptionLocktime = _redemptionLocktime;
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
        uint256 price = sharePrice();
        uint256 claimable = (
            AsMaths.min(
                req.byOperator[msg.sender].shares,
                req.totalClaimableRedemption
            )
        ).mulDiv(price, weiPerShare);
        return
            AsMaths.min(
                AsMaths.max(available(), claimable),
                _shares.mulDiv(price, weiPerShare).subBp(fees.exit) // after fees
            );
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
            paused()
                ? 0
                : AsMaths.min(
                    balanceOf(msg.sender),
                    AsMaths.max(
                        maxRedemptionClaim(_owner),
                        convertToShares(available())
                    )
                );
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
        if (owner != msg.sender || shares == 0 || balanceOf(owner) < shares)
            revert WrongRequest(msg.sender, shares);

        Erc7540Request storage request = req.byOperator[operator];
        if (request.operator != operator) request.operator = operator;

        uint256 price = sharePrice();
        if (request.shares > 0) {
            if (request.shares < shares) revert WrongRequest(owner, shares);

            req.totalRedemption -= AsMaths.min(
                req.totalRedemption,
                request.shares
            );
            req.totalUnderlying -= AsMaths.min(
                req.totalUnderlying,
                request.shares.mulDiv(request.sharePrice, weiPerShare)
            );

            uint256 increase = request.shares - shares;
            request.sharePrice =
                ((price * increase) + (request.sharePrice * request.shares)) /
                shares;
        } else {
            request.sharePrice = price;
        }

        request.shares = shares;
        request.timestamp = block.timestamp;

        req.totalRedemption += shares;
        req.totalUnderlying += shares.mulDiv(request.sharePrice, weiPerShare);

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
    function cancelRedeemRequest(
        address operator,
        address owner
    ) external nonReentrant {
        if (owner != msg.sender && operator != msg.sender)
            revert WrongRequest(msg.sender, 0);

        Erc7540Request storage request = req.byOperator[operator];
        uint256 shares = request.shares;

        if (shares == 0) revert WrongRequest(owner, 0);

        uint256 price = sharePrice();

        if (price > request.sharePrice) {
            // burn the excess shares from the loss incurred while not farming
            // with the idle funds (opportunity cost)
            uint256 opportunityCost = shares.mulDiv(
                price - request.sharePrice,
                weiPerShare
            );
            _burn(owner, opportunityCost);
        }
        uint256 amount = shares.mulDiv(request.sharePrice, weiPerShare);

        req.totalRedemption -= shares;
        req.totalUnderlying -= amount;
        if (isRequestClaimable(request.timestamp)) {
            req.totalClaimableRedemption -= shares;
            req.totalClaimableUnderlying -= amount;
        }
        request.shares = 0;
        emit RedeemRequestCanceled(owner, shares);
    }

    /**
     * @dev Returns the total number of redemption requests.
     * @return The total number of redemption requests.
     */
    function totalRedemptionRequest() external view returns (uint256) {
        return req.totalRedemption;
    }

    /**
     * @dev Returns the total amount of redemption that can be claimed.
     * @return The total amount of redemption that can be claimed.
     */
    function totalClaimableRedemption() external view returns (uint256) {
        return req.totalClaimableRedemption;
    }

    /**
     * @notice Get the pending redeem request for a specific operator
     * @param operator The operator's address
     * @return Amount of shares pending redemption
     */
    function pendingRedeemRequest(
        address operator
    ) external view returns (uint256) {
        return req.byOperator[operator].shares;
    }

    /**
     * @notice Get the pending redeem request in underlying for a specific operator
     * @param operator The operator's address
     * @return Amount of assets pending redemption
     */
    function pendingUnderlyingRequest(
        address operator
    ) external view returns (uint256) {
        Erc7540Request memory request = req.byOperator[operator];
        return
            request.shares.mulDiv(
                AsMaths.min(request.sharePrice, sharePrice()), // worst of
                weiPerShare
            );
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
                block.timestamp - req.redemptionLocktime,
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
                req.totalUnderlying,
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
        Erc7540Request memory request = req.byOperator[_owner];
        return
            isRequestClaimable(request.timestamp)
                ? AsMaths.min(request.shares, req.totalClaimableRedemption)
                : 0;
    }

    function flashLoanSimple(
        IFlashLoanReceiver receiver,
        uint256 amount,
        bytes calldata params
    ) external nonReentrant {
        uint256 available = availableBorrowable();
        if (amount > available || (totalLent + amount) > maxLoan) revert AmountTooHigh(amount);

        uint256 fee = exemptionList[msg.sender] ? 0 : amount.bp(fees.flash);
        uint256 toRepay = amount + fee;

        uint256 balanceBefore = underlying.balanceOf(address(this));
        totalLent += amount;

        underlying.safeTransferFrom(address(this), address(receiver), amount);
        receiver.executeOperation(address(underlying), amount, fee, msg.sender, params);

        if ((underlying.balanceOf(address(this)) - balanceBefore) < toRepay)
            revert FlashLoanDefault(msg.sender, amount);

        emit FlashLoan(msg.sender, amount, fee);
    }
}
