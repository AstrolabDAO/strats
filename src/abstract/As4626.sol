// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.0;

import "./As4626Abstract.sol";
import "./AsTypes.sol";
import "../interfaces/IAs4626.sol";
import "../interfaces/IERC7540RedeemReceiver.sol";
import "../libs/SafeERC20.sol";
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
        req.redemptionLocktime = 6 hours;
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
    ) public whenNotPaused returns (uint256 assets) {
        return _deposit(previewMint(_shares, _receiver), _shares, _receiver);
    }

    /**
     * @notice Mints shares to the receiver by depositing asset tokens
     * @dev Pausing the contract should prevent depositing by setting maxDepositAmount to 0
     * @param _amount Amount of asset tokens to deposit
     * @param _shares Amount of shares minted to the _receiver
     * @param _receiver Address that will get the shares
     * @return shares Amount of shares minted to the _receiver
     */
    function _deposit(
        uint256 _amount,
        uint256 _shares,
        address _receiver
    ) internal nonReentrant returns (uint256) {

        if (_receiver == address(this) || _amount == 0) revert Unauthorized();

        // do not allow minting at a price higher than the current share price
        last.sharePrice = sharePrice();

        if (_amount > maxDeposit(address(0)) || _shares > _amount.mulDiv(weiPerShare ** 2, last.sharePrice * weiPerAsset))
            revert AmountTooHigh(_amount);

        uint256 vaultAssets = asset.balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), _amount);

        // reuse the vaulAssets variable to save gas
        uint256 received = asset.balanceOf(address(this)) - vaultAssets;

        // slice the fee from the amount received (gas optimized)
        if (!exemptionList[_receiver])
            claimableAssetFees += received.revBp(fees.entry);

        // if received amount is less than the requested amount, mint proportionally less shares
        if (received < _amount)
           _shares = _shares.mulDiv(received, _amount);

        _mint(_receiver, _shares);

        emit Deposit(msg.sender, _receiver, _amount, _shares);
        return _shares;
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
        return _deposit(_amount, previewDeposit(_amount, _receiver), _receiver);
    }

    /**
     * @notice Mints shares to the receiver by depositing asset tokens
     * @dev Overloaded version with slippage control
     * @param _amount Amount of asset tokens to deposit
     * @param _minShareAmount Minimum amount of shares to be minted (1-slippage)*amount
     * @param _receiver Address that will get the shares
     * @return shares Amount of shares minted to the _receiver
     */
    function safeDeposit(
        uint256 _amount,
        uint256 _minShareAmount,
        address _receiver
    ) public whenNotPaused returns (uint256 shares) {
        shares = _deposit(_amount, convertToShares(_amount, false).subBp(exemptionList[_receiver] ? 0 : fees.entry), _receiver);
        if (shares < _minShareAmount) revert AmountTooLow(shares);
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
        address _receiver,
        address _owner
    ) internal nonReentrant returns (uint256) {
        if (_amount == 0 || _shares == 0) revert AmountTooLow(0);

        Erc7540Request storage request = req.byOwner[_owner];
        uint256 claimable = claimableRedeemRequest(_owner);
        last.sharePrice = sharePrice();

        uint256 price = (claimable >= _shares)
            ? AsMaths.min(last.sharePrice, request.sharePrice) // worst of if pre-existing request
            : last.sharePrice; // current price

        // amount/shares cannot be higher than the share price (dictated by the inline convertToAssets below)
        if (_amount > _shares.mulDiv(price * weiPerAsset, weiPerShare ** 2))
            revert AmountTooHigh(_amount);

        if (msg.sender != _owner)
            _spendAllowance(_owner, msg.sender, _shares);

        if (claimable >= _shares) {
            req.byOwner[_owner].shares -= _shares;
            req.totalRedemption -= AsMaths.min(_shares, req.totalRedemption); // min 0
            req.totalClaimableRedemption -= AsMaths.min(
                _shares,
                req.totalClaimableRedemption
            ); // min 0
        } else {
            // if the user has not requested enough shares, check if the vault cash can cover the withdrawal
            if (_shares > available().mulDiv(weiPerShare ** 2, last.sharePrice * weiPerAsset))
                revert AmountTooHigh(_shares);
        }

        if (!exemptionList[_owner])
            claimableAssetFees += _amount.revBp(fees.exit);

        _burn(_owner, _shares);

        // check if burning the shares will bring the totalSupply below the minLiquidity
        if (totalSupply() < minLiquidity.mulDiv(weiPerShare ** 2, last.sharePrice * weiPerAsset)) // eg. 1e6+(1e8+1e8)-(1e8+1e6) = 1e8
            revert Unauthorized();

        asset.safeTransfer(_receiver, _amount);

        uint256 newSupply = totalAccountedSupply();

        uint256 totalValueBefore = last.sharePrice * (newSupply + _shares);
        uint256 totalValueAfter = totalValueBefore - (_shares * price);

        // re-calculate the sharePrice dynamically to avoid sharePrice() distortion
        if (newSupply > 1)
            last.sharePrice = totalValueAfter / newSupply;

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
        if (_owner != msg.sender) revert Unauthorized();
        return _withdraw(_amount, previewWithdraw(_amount, _owner), _receiver, _owner);
    }

    /**
     * @notice Withdraw assets denominated in asset
     * @dev Overloaded version with slippage control
     * @param _amount Amount of asset tokens to withdraw
     * @param _receiver Who will get the withdrawn assets
     * @param _owner Whose shares we'll burn
     * @return amount Amount of shares burned
     */
    function safeWithdraw(
        uint256 _amount,
        uint256 _minAmount,
        address _receiver,
        address _owner
    ) public whenNotPaused returns (uint256 amount) {
        amount = _withdraw(_amount, previewWithdraw(_amount, _owner), _receiver, _owner);
        if (amount < _minAmount) revert AmountTooLow(amount);
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
    ) external whenNotPaused returns (uint256 assets) {
        if (_owner != msg.sender) revert Unauthorized();
        return _withdraw(previewRedeem(_shares, _owner), _shares, _receiver, _owner);
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
    ) external whenNotPaused returns (uint256 assets) {
        assets = _withdraw(
            previewRedeem(_shares, _owner),
            _shares, // _shares
            _receiver, // _receiver
            _owner // _owner
        );
        if (assets < _minAmountOut) revert AmountTooLow(assets);
    }

    /**
     * @notice Trigger a fee collection: mints shares to the feeCollector
     */
    function _collectFees() internal nonReentrant returns (uint256 toMint) {

        if (feeCollector == address(0))
            revert AddressZero();

        (uint256 assets, uint256 price, uint256 profit, uint256 feesAmount) = AsAccounting.computeFees(IAs4626(address(this)));

        // sum up all fees: feesAmount (perf+mgmt) + claimableAssetFees (entry+exit)
        toMint = convertToShares(feesAmount + claimableAssetFees, false);

        // do not mint nor emit event if there are no fees to collect
        if (toMint == 0)
            return 0;

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
        last.accountedAssets = assets;
        last.accountedSharePrice = price;
        last.accountedProfit = profit;
        last.accountedSupply = totalSupply();
        claimableAssetFees = 0;
    }

    /**
     * @notice Trigger a fee collection: mints shares to the feeCollector
     */
    function collectFees() external onlyKeeper returns (uint256) {
        return _collectFees();
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

        // if the vault is still paused, unpause it
        if (paused()) _unpause();
        deposit(_seedDeposit, msg.sender);
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
     * @param _receiver The owner of the shares to be redeemed
     * @return shares Amount of asset tokens that the caller should pay
     */
    function previewMint(uint256 _shares, address _receiver) public view returns (uint256) {
        return convertToAssets(_shares, true).addBp(exemptionList[_receiver] ? 0 : fees.entry);
    }

    /**
     * @notice Preview how much asset tokens the caller has to pay to acquire x shares
     * @dev Use previewMint(uint256 _shares, address _receiver) to get the exact fee exempted Amount
     * @dev This function is the ERC4626 one
     * @param _shares Amount of shares that we acquire
     * @return shares Amount of asset tokens that the caller should pay
     */
    function previewMint(uint256 _shares) external view returns (uint256) {
        return previewMint(_shares, address(0));
    }

    /**
     * @notice Previews the amount of shares that will be minted for a given deposit amount
     * @param _amount Amount of asset tokens to deposit
     * @param _receiver The future owner of the shares to be minted
     * @return shares Amount of shares that will be minted
     */
    function previewDeposit(uint256 _amount, address _receiver) public view returns (uint256 shares) {
        return convertToShares(_amount, false).revSubBp(exemptionList[_receiver] ? 0 : fees.entry);
    }

    /**
     * @notice Previews the amount of shares that will be minted for a given deposit amount
     * @dev Use previewDeposit(uint256 _amount, address _receiver) to get the exact fee exempted Amount
     * @dev This function is the ERC4626 one
     * @param _amount Amount of asset tokens to deposit
     * @return shares Amount of shares that will be minted
     */
    function previewDeposit(uint256 _amount) external view returns (uint256 shares) {
        return previewDeposit(_amount, address(0));
    }

    /**
     * @notice Preview how many shares the caller needs to burn to get his assets back
     * @dev You may get less asset tokens than you expect due to slippage
     * @param _assets How much we want to get
     * @param _owner The owner of the shares to be redeemed
     * @return How many shares will be burnt
     */
    function previewWithdraw(uint256 _assets, address _owner) public view returns (uint256) {
        return convertToShares(_assets, true).addBp(exemptionList[_owner] ? 0 : fees.exit);
    }

    /**
     * @notice Preview how many shares the caller needs to burn to get his assets back
     * @dev Use previewWithdraw(uint256 _assets, address _owner) to get the exact fee exempted amount
     * @dev This function is the ERC4626 one
     * @param _assets How much we want to get
     * @return How many shares will be burnt
     */
    function previewWithdraw(uint256 _assets) external view returns (uint256) {
        return previewWithdraw(_assets, address(0));
    }

    /**
     * @notice Preview how many asset tokens the caller will get for burning his _shares
     * @param _shares Amount of shares that we burn
     * @param _owner The owner of the shares to be redeemed
     * @return Preview amount of asset tokens that the caller will get for his shares
     */
    function previewRedeem(uint256 _shares, address _owner) public view returns (uint256) {
        return convertToAssets(_shares, false).revSubBp(exemptionList[_owner] ? 0 : fees.exit);
    }

    /**
     * @notice Preview how many asset tokens the caller will get for burning his _shares
     * @dev Use previewRedeem(uint256 _shares, address _owner) to get the exact fee exempted amount
     * @dev This function is the ERC4626 one
     * @param _shares Amount of shares that we burn
     * @return Preview amount of asset tokens that the caller will get for his shares
     */
    function previewRedeem(uint256 _shares) external view returns (uint256) {
        return previewRedeem(_shares, address(0));
    }

    /**
     * @return The maximum amount of assets that can be deposited
     */
    function maxDeposit(address) public view returns (uint256) {
        return paused() ? 0 : maxTotalAssets.subMax0(totalAssets());
    }

    /**
     * @return The maximum amount of shares that can be minted
     */
    function maxMint(address) public view returns (uint256) {
        return paused() ? 0 : convertToShares(maxDeposit(address(0)), false);
    }

    /**
     * @return The maximum amount of assets that can be withdrawn
     */
    function maxWithdraw(address _owner) public view returns (uint256) {
        return paused() ? 0 : convertToAssets(maxRedeem(_owner), false);
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
                        claimableRedeemRequest(_owner),
                        convertToShares(available(), false)
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
    //     address operator,
    //     address _owner,
    //     bytes memory _data
    // ) external virtual nonReentrant whenNotPaused returns (uint256 _requestId) {}

    /**
     * @notice Initiate a redeem request for shares
     * @param _shares Amount of shares to redeem
     * @param _operator Address initiating the request
     * @param _owner The owner of the shares to be redeemed
     */
    function requestRedeem(
        uint256 _shares,
        address _operator,
        address _owner,
        bytes memory _data
    ) public nonReentrant whenNotPaused returns (uint256 _requestId) {
        if (_operator != msg.sender || (_owner != msg.sender && allowance(_owner, _operator) < _shares))
            revert Unauthorized();
        if (_shares == 0 || balanceOf(_owner) < _shares)
            revert AmountTooLow(_shares);

        Erc7540Request storage request = req.byOwner[_owner];
        if (request.operator != _operator) request.operator = _operator;

        last.sharePrice = sharePrice();
        if (request.shares > 0) {
            if (request.shares > _shares)
                revert AmountTooLow(_shares);

            // reinit the request (re-added lower)
            req.totalRedemption -= AsMaths.min(
                req.totalRedemption,
                request.shares
            );
            // compute request vwap
            request.sharePrice =
                ((last.sharePrice * (_shares - request.shares)) + (request.sharePrice * request.shares)) /
                _shares;
        } else {
            request.sharePrice = last.sharePrice;
        }

        requestId = ++_requestId;
        request.requestId = _requestId;
        request.shares = _shares;
        request.timestamp = block.timestamp;
        req.totalRedemption += _shares;

        if(_data.length != 0) {
        // the caller contract must return the bytes4 value "0x0102fde4"
            if(IERC7540RedeemReceiver(msg.sender).onERC7540RedeemReceived(_operator, _owner, _requestId, _data) != 0x0102fde4)
                revert Unauthorized();
        }
        emit RedeemRequest(_owner, _operator, _owner, _shares);
        return requestId;
    }

    /**
     * @notice Initiate a withdraw request for assets denominated in asset
     * @param _amount Amount of asset tokens to withdraw
     * @param _operator Address initiating the request
     * @param _owner The owner of the shares to be redeemed
     * @param _data Additional data
     * @return requestId The ID of the withdraw request
     */
    function requestWithdraw(
        uint256 _amount,
        address _operator,
        address _owner,
        bytes memory _data
    ) external returns (uint256) {
        return requestRedeem(convertToShares(_amount, false), _operator, _owner, _data);
    }

    // /**
    //  * @notice Cancel a deposit request
    //  * @param operator Address initiating the request
    //  * @param owner The owner of the shares to be redeemed
    //  */
    // function cancelDepositRequest(
    //     address operator,
    //     address owner
    // ) external virtual nonReentrant {}

    /**
     * @notice Cancel a redeem request
     * @param _operator Address initiating the request
     * @param _owner The owner of the shares to be redeemed
     */
    function cancelRedeemRequest(
        address _operator,
        address _owner
    ) external nonReentrant {
        Erc7540Request storage request = req.byOwner[_owner];
        uint256 shares = request.shares;

        if (_operator != msg.sender || (_owner != msg.sender && allowance(_owner, _operator) < shares))
            revert Unauthorized();
        if (shares == 0) revert AmountTooLow(0);

        last.sharePrice = sharePrice();
        uint256 opportunityCost = 0;
        if (last.sharePrice > request.sharePrice) {
            // burn the excess shares from the loss incurred while not farming
            // with the idle funds (opportunity cost)
            opportunityCost = shares.mulDiv(
                last.sharePrice - request.sharePrice,
                weiPerShare
            ); // eg. 1e8+1e8-1e8 = 1e8
            _burn(_owner, opportunityCost);
        }

        req.totalRedemption -= shares;
        if (isRequestClaimable(request.timestamp))
            req.totalClaimableRedemption -= shares;

        // Adjust the operator's allowance after burning shares, only if the operator is different from the owner
        if (opportunityCost > 0 && _owner != msg.sender) {
            uint256 currentAllowance = allowance(_owner, _operator);
            _approve(_owner, _operator, currentAllowance - shares);
        }
        request.shares = 0;
        emit RedeemRequestCanceled(_owner, shares);
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
     * @notice Get the pending redeem request for a specific owner
     * @param _owner The owner's address
     * @return Amount of shares pending redemption
     */
    function pendingRedeemRequest(
        address _owner
    ) external view returns (uint256) {
        return req.byOwner[_owner].shares;
    }

    /**
     * @notice Get the pending redeem request in asset for a specific owner
     * @param _owner The owner's address
     * @return Amount of assets pending redemption
     */
    function pendingAssetRequest(
        address _owner
    ) external view returns (uint256) {
        Erc7540Request memory request = req.byOwner[_owner];
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
            block.timestamp >= AsMaths.min(
                requestTimestamp + req.redemptionLocktime,
                last.liquidate
            );
    }

    /**
     * @notice Get the maximum claimable redemption amount
     * @return The maximum claimable redemption amount
     */
    function maxClaimableAsset() internal view returns (uint256) {
        return
            AsMaths.min(convertToAssets(req.totalRedemption, false), availableClaimable());
    }

    /**
     * @notice Get the maximum redemption claim for a specific owner
     * @param _owner The owner's address
     * @return The maximum redemption claim for the owner
     */
    function claimableRedeemRequest(address _owner) public view returns (uint256) {
        Erc7540Request memory request = req.byOwner[_owner];
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

        if (amount > availableBorrowable() || amount > maxLoan) revert AmountTooHigh(amount);

        uint256 fee = exemptionList[msg.sender] ? 0 : amount.bp(fees.flash);
        uint256 balanceBefore = asset.balanceOf(address(this));

        totalLent += amount;

        asset.safeTransfer(address(receiver), amount);
        receiver.executeOperation(address(asset), amount, fee, msg.sender, params);

        if ((asset.balanceOf(address(this)) - balanceBefore) < fee)
            revert FlashLoanDefault(msg.sender, amount);

        emit FlashLoan(msg.sender, amount, fee);
    }
}
