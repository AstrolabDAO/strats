// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./As4626Abstract.sol";
import "./AsTypes.sol";
import "../libs/AsMaths.sol";
import "../libs/AsAccounting.sol";
import "hardhat/console.sol";

abstract contract As4626 is As4626Abstract {

    using AsMaths for uint256;
    using AsMaths for int256;
    using SafeERC20 for ERC20;

    /**
     * @dev Initialize the contract after deployment.
     */
    function _init(
        Fees memory _fees,
        address _underlying,
        address _feeCollector
    ) internal virtual {
        console.log("As4626.init");
        // check that the fees are not too high
        if (!AsAccounting.checkFees(_fees, MAX_FEES)) revert FeeError();
        fees = _fees;
        underlying = ERC20(_underlying);
        feeCollector = _feeCollector;

        // use the same decimals as the underlying
        shareDecimals = ERC20(_underlying).decimals();
        weiPerShare = 10**shareDecimals;
        feeCollectedAt = Checkpoint(block.timestamp, weiPerShare);
    }

    /// @notice Mints shares to the receiver by depositing underlying tokens
    /// @param _shares Amount of shares minted to the _receiver
    /// @param _receiver Shares receiver
    /// @return assets Amount of assets deposited
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
        emit Deposited(msg.sender, _receiver, assets, _shares);
    }

    /// @notice Mints shares to the receiver by depositing underlying tokens
    /// @dev Pausing the contract should prevent depositing by setting maxDepositAmount to 0
    /// @param _amount The amount of underlying tokens to deposit
    /// @param _receiver The address that will get the shares
    /// @param _minShareAmount Minimum amount of shares to be minted, like slippage on Uniswap
    /// @return shares the amount of shares minted to the _receiver
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

        // save totalAssets before transfering
        uint256 assetsAvailable = totalAssets();
        // Moving value
        underlying.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 supply = totalSupply();

        // slice the fee from the amount (gas optimized)
        if (feeCollector != address(0)) {
            uint256 fee = _amount.mulDiv(fees.entry, AsMaths.BP_BASIS);
            claimableUnderlyingFees += fee;
            _amount -= fee;
            _minShareAmount -= convertToShares(fee);
        }

        shares = supply == 0
            ? _amount.mulDiv(sharePrice(), weiPerShare)
            : _amount.mulDiv(supply, assetsAvailable);

        if (shares == 0 || shares < _minShareAmount) {
            revert AmountTooLow(shares);
        }

        // mint shares
        _mint(_receiver, shares);
        emit Deposited(msg.sender, _receiver, _amount, shares);
    }

    function previewDeposit(
        uint256 _amount
    ) public view returns (uint256 shares) {
        return
            convertToShares(_amount.mulDiv(AsMaths.BP_BASIS - fees.entry, AsMaths.BP_BASIS));
    }

    // @inheritdoc _deposit
    /// @dev Beware, there's no slippage control - use safeDeposit if you want it
    function deposit(
        uint256 _amount,
        address _receiver
    ) public returns (uint256 shares) {
        return _deposit(_amount, _receiver, 0);
    }

    // @inheritdoc _deposit
    /// @dev Overloaded version with slippage control
    function safeDeposit(
        uint256 _amount,
        address _receiver,
        uint256 _minShareAmount
    ) public returns (uint256 shares) {
        return _deposit(_amount, _receiver, _minShareAmount);
    }

    /// @notice The vault takes a small fee to prevent share price updates arbitrages
    /// @dev Fees should already have been taken into account
    /// @param _amount Amount of assets to pull from the crate
    /// @param _shares Amount of shares to burn
    /// @param _minAmountOut The minimum amount of assets we'll accept
    /// @param _receiver Who will get the withdrawn assets
    /// @param _owner Whose shares we'll burn
    function _withdraw(
        uint256 _amount,
        uint256 _shares,
        uint256 _minAmountOut,
        address _receiver,
        address _owner
    ) internal nonReentrant whenNotPaused returns (uint256 recovered) {
        if (_amount == 0 || _shares == 0) revert AmountTooLow(0);

        if (_shares >= totalSupply())
            _shares = totalSupply() - 1; // never redeem all shares

        // spend the allowance if the msg.sender isn't the receiver
        if (msg.sender != _owner) {
            _spendAllowance(_owner, msg.sender, _shares);
        }

        uint256 assets = convertToAssets(_shares);

        // Check for rounding error since we round down in previewRedeem.
        if (assets == 0) revert AmountTooLow(assets);

        // slice fee from burnt shares
        if (feeCollector != address(0)) {
            uint256 fee = _shares.mulDiv(fees.exit, AsMaths.BP_BASIS);
            _amount -= convertToAssets(fee);
            _transfer(_owner, address(this), fee);
            _shares -= fee;
        }

        // burn the shares
        _burn(_owner, _shares);

        uint256 assetBal = available();

        // If there are enough funds in the vault, we just send them
        if (assetBal > 0 && assetBal >= _amount) {
            recovered = _amount;
            underlying.safeTransfer(_receiver, recovered);
        } else {
            revert InsufficientFunds(assetBal);
        }

        if (_minAmountOut > 0 && recovered < _minAmountOut)
            revert AmountTooLow(recovered);

        emit Withdrawn(msg.sender, _receiver, _owner, _amount, _shares);
    }

    // @inheritdoc _withdraw
    /// @notice Withdraw assets denominated in underlying
    /// @dev Beware, there's no slippage control - use safeWithdraw if you want it
    function withdraw(
        uint256 _amount,
        address _receiver,
        address _owner
    ) external virtual returns (uint256 shares) {
        // This represents the amount of shares that we're about to burn
        shares = convertToShares(_amount);
        _withdraw(_amount, shares, 0, _receiver, _owner);
    }

    // @inheritdoc withdraw
    /// @dev Overloaded version with slippage control
    /// @param _minAmount The minimum amount of assets we'll accept
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

    /// @notice Redeem shares for their underlying value
    /// Beware, there's no slippage control - you need to use the overloaded function if you want it
    /// @param _shares The amount of shares to redeem
    /// @param _receiver Who will get the withdrawn assets
    /// @param _owner Whose shares we'll burn
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

    // @inheritdoc redeem
    /// @dev Overloaded version with slippage control
    /// @param _minAmountOut The minimum amount of assets accepted
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

    /// @notice Trigger a fee collection: mints shares to the feeCollector
    /// @dev This function can be called by any keeper
    function collectFees() external onlyKeeper {
        (
            uint256 perfFeesAmount,
            uint256 mgmtFeesAmount,
            uint256 profit
        ) = AsAccounting.computeFees(
            totalAssets(),
            sharePrice(),
            fees,
            feeCollectedAt);

        if (feeCollector == address(0)) revert AddressZero();
        if (profit == 0) return;

        uint256 outstandingFees = perfFeesAmount +
            mgmtFeesAmount +
            claimableUnderlyingFees;
        uint256 sharesToMint = convertToShares(outstandingFees);

        _mint(feeCollector, sharesToMint);
        claimableUnderlyingFees = 0;

        feeCollectedAt = Checkpoint(block.timestamp, sharePrice());

        emit FeesCollected(
            profit,
            totalAssets(),
            perfFeesAmount,
            mgmtFeesAmount,
            sharesToMint,
            feeCollector
        );
    }

    /// @notice Pause the crate
    function pause() external onlyManager {
        _pause();
        // This prevents deposit
        maxTotalAssets = 0;
    }

    /// @notice Unpause the crate
    function unpause() external onlyManager {
        _unpause();
    }

    /// @notice Update Fee Recipient address
    function setFeeCollector(address _feeCollector) external onlyAdmin {
        if (_feeCollector == address(0)) revert AddressZero();
        feeCollector = _feeCollector;
        emit FeeCollectorUpdated(feeCollector);
    }

    /// @notice Set the max amount of total assets that can be deposited
    /// @param _maxTotalAssets The maximum amount of assets
    function setMaxTotalAssets(uint256 _maxTotalAssets) public onlyAdmin {
        maxTotalAssets = _maxTotalAssets;
        emit MaxTotalAssetsSet(_maxTotalAssets);
    }

    /// @notice Set maxTotalAssets + deposits seed liquidity into the vault
    /// @dev Deposits are disabled when the assets reach this limit
    /// @param _seedDeposit amount of assets to seed the vault
    /// @param _maxTotalAssets max amount of assets
    function initialize(uint256 _seedDeposit, uint256 _maxTotalAssets) external onlyManager {

        if (_seedDeposit < (minLiquidity - totalAssets()))
            revert LiquidityTooLow(_seedDeposit);
        // seed the vault with some assets if it's empty
        setMaxTotalAssets(_maxTotalAssets);
        // 1e8 is the minimum amount of assets to seed the vault (1 USDC or .1Gwei ETH)
        // allowance should be given to the vault before calling this function
        uint256 seedDeposit = minLiquidity;
        if (totalSupply() == 0) {
            _deposit(
                seedDeposit,
                msg.sender,
                (seedDeposit * sharePrice()) / weiPerShare
            );
        }
        _unpause();
    }

    /// @notice Set the fees if compliant with MAX_FEES constant
    /// @dev Maximum fees are registered as constants
    /// @param _fees.perf Fee on performance
    function setFees(Fees memory _fees) external onlyAdmin {
        if (!AsAccounting.checkFees(_fees, MAX_FEES)) revert FeeError();
        fees = _fees;
        emit FeesUpdated(fees.perf, fees.mgmt, fees.entry, fees.exit);
    }

    /// @notice Set the minimum amount of assets to seed the vault
    /// @dev This is to avoid dust amounts of assets
    /// @param _minLiquidity The minimum amount of assets to seed the vault
    function setMinLiquidity(uint256 _minLiquidity) external onlyAdmin {
        minLiquidity = _minLiquidity;
    }

    /// @notice Set the cooldown period for realizing profits
    /// @dev This is to avoid MEV/arbs
    /// @param _profitCooldown The cooldown period for realizing profits
    function setProfitCooldown(uint256 _profitCooldown) external onlyAdmin {
        profitCooldown = _profitCooldown;
    }


    /// @notice Convert how much shares you can get for your assets
    /// @param _assets Amount of assets to convert
    /// @return The amount of shares you can get for your assets
    function convertToShares(uint256 _assets) public view returns (uint256) {
        uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.
        // shares = assets * supply / totalDebt
        return supply == 0 ? _assets : _assets.mulDiv(supply, totalAssets());
    }

    /// @notice Convert how much asset tokens you can get for your shares
    /// @dev Bear in mind that some negative slippage may happen
    /// @param _shares amount of shares to covert
    /// @return The amount of asset tokens you can get for your shares
    function convertToAssets(uint256 _shares) public view returns (uint256) {
        uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.
        return supply == 0 ? _shares : _shares.mulDiv(totalAssets(), supply);
    }

    /// @notice Preview how much asset tokens the caller has to pay to acquire x shares
    /// @param _shares Amount of shares that we acquire
    /// @return shares Amount of asset tokens that the caller should pay
    function previewMint(uint256 _shares) public view returns (uint256) {
        return convertToAssets(_shares);
    }

    /// @notice Preview how many shares the caller needs to burn to get his assets back
    /// @dev You may get less asset tokens than you expect due to slippage
    /// @param _assets How much we want to get
    /// @return How many shares will be burnt
    function previewWithdraw(uint256 _assets) public view returns (uint256) {
        return
            convertToShares(_assets.mulDiv(AsMaths.BP_BASIS, AsMaths.BP_BASIS - fees.exit));
    }

    /// @notice Preview how many underlying tokens the caller will get for burning his _shares
    /// @param _shares Amount of shares that we burn
    /// @return Preview amount of underlying tokens that the caller will get for his shares
    function previewRedeem(uint256 _shares) public view returns (uint256) {
        uint256 afterFees = convertToAssets(_shares).mulDiv(
            AsMaths.BP_BASIS,
            AsMaths.BP_BASIS - fees.exit
        );
        return available() >= afterFees ? afterFees : 0;
    }

    /// @return The maximum amount of assets that can be deposited
    function maxDeposit(address) public view returns (uint256) {
        uint256 _totalAssets = totalAssets();
        return _totalAssets > maxTotalAssets ? 0 : maxTotalAssets - _totalAssets;
    }

    /// @return The maximum amount of shares that can be minted
    function maxMint(address) public view returns (uint256) {
        return convertToShares(maxDeposit(address(0)));
    }

    /// @return The maximum amount of assets that can be withdrawn
    function maxWithdraw(address _owner) external view returns (uint256) {
        return paused() ? 0 : convertToAssets(balanceOf(_owner));
    }

    /// @return The maximum amount of shares that can be redeemed
    function maxRedeem(address _owner) external view returns (uint256) {
        return paused() ? 0 : balanceOf(_owner);
    }

    receive() external payable {}
}
