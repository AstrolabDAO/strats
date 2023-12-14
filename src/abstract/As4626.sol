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

    event FeeCollection(
        address indexed collector,
        uint256 totalAssets,
        uint256 sharePrice,
        uint256 profit,
        uint256 feesAmount,
        uint256 sharesMinted
    );

    receive() external payable {}

    /**
     * @dev Initializes the contract with the provided ERC20 metadata, core addresses, and fees.
     * Only the admin can call this function.
     * @param _erc20Metadata The ERC20 metadata including name, symbol, and decimals.
     * @param _coreAddresses The core addresses including the fee collector address.
     * @param _fees The fees structure.
     */
    function init(
        Erc20Metadata calldata _erc20Metadata,
        CoreAddresses calldata _coreAddresses,
        Fees calldata _fees
    ) public virtual onlyAdmin {
        // check that the fees are not too high
        setFees(_fees);
        feeCollector = _coreAddresses.feeCollector;
        last.accountedSharePrice = weiPerShare;
        last.accountedProfit = weiPerShare;
        last.feeCollection = uint64(block.timestamp);
        last.liquidate = uint64(block.timestamp);
        last.harvest = uint64(block.timestamp);
        last.invest = uint64(block.timestamp);
        ERC20._init(_erc20Metadata.name, _erc20Metadata.symbol, _erc20Metadata.decimals);
    }

    /**
     * @notice Mints shares to the receiver by depositing asset tokens
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
        asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(_receiver, _shares);
        emit Deposit(msg.sender, _receiver, assets, _shares);
    }

    /**
     * @notice Mints shares to the receiver by depositing asset tokens
     * @dev Pausing the contract should prevent depositing by setting maxDepositAmount to 0
     * @param _amount Amount of asset tokens to deposit
     * @param _receiver Address that will get the shares
     * @param _minShareAmount Minimum amount of shares to be minted (1-slippage)*amount
     * @return shares Amount of shares minted to the _receiver
     */
    function _deposit(
        uint256 _amount,
        uint256 _shares,
        uint256 _minShareAmount,
        address _receiver
    ) internal nonReentrant returns (uint256 shares) {

        if (_receiver == address(this) || _amount == 0) revert Unauthorized();
        // do not allow minting at a price higher than the current share price
        if (_amount > maxDeposit(address(0)) || _shares > convertToShares(_amount))
            revert AmountTooHigh(_amount);

        asset.safeTransferFrom(msg.sender, address(this), _amount);

        // slice the fee from the amount (gas optimized)
        if (!exemptionList[_receiver])
            claimableAssetFees += _amount.revBp(fees.entry);

        if (shares < _minShareAmount)
            revert AmountTooLow(shares);

        // mint shares
        _mint(_receiver, shares);
        emit Deposit(msg.sender, _receiver, _amount, shares);
    }

    /**
     * @notice Mints shares to the receiver by depositing asset tokens
     * @dev Unlike safeDeposit, there's no slippage control here
     * @param _amount Amount of asset tokens to deposit
     * @param _receiver Address that will get the shares
     * @return shares Amount of shares minted to the _receiver
     */
    function deposit(
        uint256 _amount,
        address _receiver
    ) public whenNotPaused returns (uint256 shares) {
        return _deposit(_amount, convertToShares(_amount).subBp(exemptionList[msg.sender] ? 0 : fees.entry), 1, _receiver);
    }

    /**
     * @notice Mints shares to the receiver by depositing asset tokens
     * @dev Overloaded version with slippage control
     * @param _amount Amount of asset tokens to deposit
     * @param _receiver Address that will get the shares
     * @param _minShareAmount Minimum amount of shares to be minted (1-slippage)*amount
     * @return shares Amount of shares minted to the _receiver
     */
    function safeDeposit(
        uint256 _amount,
        address _receiver,
        uint256 _minShareAmount
    ) public whenNotPaused returns (uint256 shares) {
        return _deposit(_amount, convertToShares(_amount).subBp(exemptionList[msg.sender] ? 0 : fees.entry), _minShareAmount, _receiver);
    }

    /**
     * @notice Withdraw assets denominated in asset
     * @dev Unlike safeWithdraw, there's no slippage control here
     * @param _amount Amount of asset tokens to withdraw
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

        // check if burning the shares will bring the totalSupply below the minLiquidity
        if (_shares >= (totalSupply() - minLiquidity.mulDiv(weiPerShare ** 2, price * weiPerAsset))) // eg. 1e6+(1e8+1e8)-(1e8+1e6) = 1e8
            revert Unauthorized();

        // amount/shares cannot be higher than the share price (dictated by the inline convertToAssets below)
        if (_amount >= _shares.mulDiv(price * weiPerAsset, weiPerShare ** 2))
            revert AmountTooHigh(_amount);

        if (msg.sender != _owner)
            _spendAllowance(_owner, msg.sender, _shares);

        Erc7540Request storage request = req.byOperator[_receiver];
        uint256 claimable = maxRedemptionClaim(_owner);

        price = (claimable >= _shares)
            ? AsMaths.min(price, request.sharePrice) // worst of if pre-existing request
            : price; // current price

        if (claimable >= _shares) {
            req.byOperator[_receiver].shares -= _shares;
            req.totalRedemption -= AsMaths.min(_shares, req.totalRedemption); // min 0
            req.totalClaimableRedemption -= AsMaths.min(
                _shares,
                req.totalClaimableRedemption
            ); // min 0
        }

        if (!exemptionList[_owner])
            claimableAssetFees += _amount.revBp(fees.exit);

        if (_amount <= _minAmountOut) revert AmountTooLow(_amount);

        _burn(_owner, _shares);
        asset.safeTransfer(_receiver, _amount);

        emit Withdraw(msg.sender, _receiver, _owner, _amount, _shares);
        return _amount;
    }

    /**
     * @notice Withdraw assets denominated in asset
     * @dev Beware, there's no slippage control - use safeWithdraw if you want it
     * @param _amount Amount of asset tokens to withdraw
     * @param _receiver Who will get the withdrawn assets
     * @param _owner Whose shares we'll burn
     * @return shares Amount of shares burned
     */
    function withdraw(
        uint256 _amount,
        address _receiver,
        address _owner
    ) external whenNotPaused returns (uint256) {
        return _withdraw(_amount, convertToShares(_amount).addBp(exemptionList[_owner] ? 0 : fees.exit), 1, _receiver, _owner);
    }

    /**
     * @notice Withdraw assets denominated in asset
     * @dev Overloaded version with slippage control
     * @param _amount Amount of asset tokens to withdraw
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
    ) public whenNotPaused returns (uint256) {
        return _withdraw(_amount, convertToShares(_amount).addBp(exemptionList[_owner] ? 0 : fees.exit), _minAmount, _receiver, _owner);
    }

    /**
     * @notice Redeem shares for their asset value
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
                convertToAssets(_shares).subBp(exemptionList[_owner] ? 0 : fees.exit),
                _shares,
                1,
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
                convertToAssets(_shares).subBp(exemptionList[_owner] ? 0 : fees.exit),
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

        if (feeCollector == address(0))
            revert AddressZero();

        (uint256 assets, uint256 price, uint256 profit, uint256 feesAmount) = AsAccounting.computeFees(IAs4626(address(this)));

        if (profit == 0) return;
        uint256 toMint = convertToShares(feesAmount + claimableAssetFees);
        emit FeeCollection(
            feeCollector,
            assets,
            price,
            profit, // basis AsMaths.BP_BASIS**2
            feesAmount,
            toMint
        );
        _mint(feeCollector, toMint);
        last.feeCollection = uint64(block.timestamp);
        last.accountedTotalAssets = assets;
        last.accountedSharePrice = price;
        last.accountedProfit = profit;
        last.accountedTotalSupply = totalSupply();
        claimableAssetFees = 0;
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
    }

    /**
     * @notice Sets the internal slippage
     * @param _slippageBps array of input tokens
     */
    function setMaxSlippageBps(uint16 _slippageBps) external onlyManager {
        maxSlippageBps = _slippageBps;
    }

    /**
     * @dev Sets the maximum loan amount
     * @param _maxLoan The new maximum loan amount
     */
    function setMaxLoan(uint256 _maxLoan) external onlyManager {
        maxLoan = _maxLoan;
    }

    /**
     * @notice Set the max amount of total assets that can be deposited
     * @param _maxTotalAssets The maximum amount of assets
     */
    function setMaxTotalAssets(uint256 _maxTotalAssets) public onlyAdmin {
        maxTotalAssets = _maxTotalAssets;
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

        if (totalSupply() < minLiquidity)
            deposit(_seedDeposit, msg.sender);

        // if the vault is still paused, unpause it
        if (paused()) _unpause();
    }

    /**
     * @notice Set the fees if compliant with MAX_FEES constant
     * @dev Maximum fees are registered as constants
     * @param _fees.perf Fee on performance
     */
    function setFees(Fees calldata _fees) public onlyAdmin {
        if (!AsAccounting.checkFees(_fees)) revert Unauthorized();
        fees = _fees;
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
    function previewMint(uint256 _shares) external view returns (uint256) {
        return convertToAssets(_shares).addBp(exemptionList[msg.sender] ? 0 : fees.entry);
    }

    /**
     * @notice Previews the amount of shares that will be minted for a given deposit amount
     * @param _amount Amount of asset tokens to deposit
     * @return shares Amount of shares that will be minted
     */
    function previewDeposit(
        uint256 _amount
    ) public view returns (uint256 shares) {
        return convertToShares(_amount).subBp(exemptionList[msg.sender] ? 0 : fees.entry);
    }

    /**
     * @notice Preview how many shares the caller needs to burn to get his assets back
     * @dev You may get less asset tokens than you expect due to slippage
     * @param _assets How much we want to get
     * @return How many shares will be burnt
     */
    function previewWithdraw(uint256 _assets) external view returns (uint256) {
        return convertToShares(_assets).addBp(exemptionList[msg.sender] ? 0 : fees.exit);
    }

    /**
     * @notice Preview how many asset tokens the caller will get for burning his _shares
     * @param _shares Amount of shares that we burn
     * @return Preview amount of asset tokens that the caller will get for his shares
     */
    function previewRedeem(uint256 _shares) external view returns (uint256) {
        return convertToAssets(_shares).subBp(exemptionList[msg.sender] ? 0 : fees.exit);
    }

    /**
     * @return The maximum amount of assets that can be deposited
     */
    function maxDeposit(address) public view returns (uint256) {
        return maxTotalAssets.subMax0(totalAssets());
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

    // /**
    //  * @notice Initiate a deposit request for assets denominated in asset
    //  * @param assets Amount of asset tokens to deposit
    //  * @param operator Address initiating the request
    //  */
    // function requestDeposit(
    //     uint256 assets,
    //     address operator
    // ) external virtual {}

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
            revert Unauthorized();

        Erc7540Request storage request = req.byOperator[operator];
        if (request.operator != operator) request.operator = operator;

        uint256 price = sharePrice();
        if (request.shares > 0) {
            if (request.shares < shares) revert AmountTooHigh(shares);

            req.totalRedemption -= AsMaths.min(
                req.totalRedemption,
                request.shares
            );
            // compute request vwap
            request.sharePrice =
                ((price * (request.shares - shares)) + (request.sharePrice * request.shares)) /
                shares;
        } else {
            request.sharePrice = price;
        }

        request.shares = shares;
        request.timestamp = block.timestamp;

        req.totalRedemption += shares;

        emit RedeemRequest(owner, operator, owner, shares);
    }

    /**
     * @notice Initiate a withdraw request for assets denominated in asset
     * @param _amount Amount of asset tokens to withdraw
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

    // /**
    //  * @notice Cancel a deposit request
    //  * @param operator Address initiating the request
    //  * @param owner The owner of the shares to be redeemed
    //  */
    // function cancelDepositRequest(
    //     address operator,
    //     address owner
    // ) external virtual {}

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
            revert Unauthorized();

        Erc7540Request storage request = req.byOperator[operator];
        uint256 shares = request.shares;

        if (shares == 0) revert AmountTooLow(0);

        uint256 price = sharePrice();

        if (price > request.sharePrice) {
            // burn the excess shares from the loss incurred while not farming
            // with the idle funds (opportunity cost)
            uint256 opportunityCost = shares.mulDiv(
                price - request.sharePrice,
                weiPerShare
            ); // eg. 1e8+1e8-1e8 = 1e8
            _burn(owner, opportunityCost);
        }

        req.totalRedemption -= shares;
        if (isRequestClaimable(request.timestamp))
            req.totalClaimableRedemption -= shares;

        request.shares = 0;
        emit RedeemRequestCanceled(owner, shares);
    }

    /**
     * @dev Returns the total number of redemption requests
     * @return The total number of redemption requests
     */
    function totalRedemptionRequest() external view returns (uint256) {
        return req.totalRedemption;
    }

    /**
     * @dev Returns the total amount of redemption that can be claimed
     * @return The total amount of redemption that can be claimed
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
     * @notice Get the pending redeem request in asset for a specific operator
     * @param operator The operator's address
     * @return Amount of assets pending redemption
     */
    function pendingAssetRequest(
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
    function maxClaimableAsset() internal view returns (uint256) {
        return
            AsMaths.min(convertToAssets(req.totalRedemption), availableClaimable());
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

    /**
     * @dev Executes a flash loan by transferring a specified amount of tokens to a receiver contract and executing an operation.
     * @param receiver The contract that will receive the flash loan tokens and execute the operation.
     * @param amount The amount of tokens to be borrowed in the flash loan.
     * @param params Additional parameters to be passed to the receiver contract's executeOperation function.
     */
    function flashLoanSimple(
        IFlashLoanReceiver receiver,
        uint256 amount,
        bytes calldata params
    ) external nonReentrant {
        uint256 available = availableBorrowable();
        if (amount > available || (totalLent + amount) > maxLoan) revert AmountTooHigh(amount);

        uint256 fee = exemptionList[msg.sender] ? 0 : amount.bp(fees.flash);
        uint256 toRepay = amount + fee;

        uint256 balanceBefore = asset.balanceOf(address(this));
        totalLent += amount;

        asset.safeTransferFrom(address(this), address(receiver), amount);
        receiver.executeOperation(address(asset), amount, fee, msg.sender, params);

        if ((asset.balanceOf(address(this)) - balanceBefore) < toRepay)
            revert FlashLoanDefault(msg.sender, amount);

        emit FlashLoan(msg.sender, amount, fee);
    }
}
