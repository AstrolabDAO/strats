// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.0;

import "@astrolabs/swapper/contracts/interfaces/ISwapper.sol";
import "../interfaces/IStrategyV5.sol";
import "./StrategyV5Abstract.sol";
import "./AsProxy.sol";
import "../libs/SafeERC20.sol";
import "../libs/AsArrays.sol";
import "../libs/AsMaths.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title StrategyV5 Abstract - implemented by all strategies
 * @author Astrolab DAO
 * @notice All StrategyV5 calls are delegated to the agent (StrategyV5Agent)
 * @dev Make sure all state variables are in StrategyV5Abstract to match proxy/implementation slots
 */
abstract contract StrategyV5 is StrategyV5Abstract, AsProxy {
    using AsMaths for uint256;
    using AsMaths for int256;
    using AsArrays for bytes[];
    using SafeERC20 for IERC20;

    constructor() StrategyV5Abstract() {}

    /**
     * @notice Initialize the strategy
     * @param _params StrategyBaseParams struct containing strategy parameters
     */
    function _init(StrategyBaseParams calldata _params) internal onlyAdmin {
        // setExemption(msg.sender, true);
        // done in As4626 but required for swapper
        stratProxy = address(this);
        agent = _params.coreAddresses.agent;
        wgas = IWETH9(_params.coreAddresses.wgas);
        if (agent == address(0)) revert AddressZero();
        _delegateWithSignature(
            agent, // erc20Metadata.................coreAddresses................................fees...................inputs.inputWeights.rewardTokens
            "init(((string,string,uint8),(address,address,address,address,address),(uint64,uint64,uint64,uint64,uint64),address[],uint16[],address[]))" // StrategyV5Agent.init(_params)
        );
    }

    /**
     * @notice Returns the StrategyV5Agent proxy initialization state
     */
    function initialized() public view override returns (bool) {
        return agent != address(0) && address(asset) != address(0);
    }

    /**
     * @notice Returns the address of the implementation
     */
    function _implementation() internal view override returns (address) {
        return agent;
    }

    /**
     * @notice Changes the strategy asset token (automatically pauses the strategy)
     * called from oracle implementations
     * @param _asset Address of the token
     * @param _swapData Swap callData oldAsset->newAsset
     */
    function _updateAsset(
        address _asset,
        bytes calldata _swapData
    ) internal {
        _delegateWithSignature(
            agent,
            "updateAsset(address,bytes)" // StrategyV5Agent.updateAsset(_asset, _swapData)
        );
    }

    /**
     * @notice Sets the agent (StrategyV5Agent implementation)
     * @param _agent The new agent address
     */
    function updateAgent(address _agent) external onlyAdmin {
        if (_agent == address(0)) revert AddressZero();
        agent = _agent;
    }

    /**
     * @notice Withdraw asset function, can remove all funds in case of emergency
     * @param _amounts Amounts of asset to withdraw
     * @param _params Swaps calldata
     * @return assetsRecovered Amount of asset withdrawn
     */
    function _liquidate(
        uint256[8] calldata _amounts, // from previewLiquidate()
        bytes[] memory _params
    ) internal virtual returns (uint256 assetsRecovered) {}

    /**
     * @dev Reverts if slippage is too high unless panic is true. Extends the functionality of the _liquidate function
     * @param _amounts Amount of inputs to liquidate (in asset)
     * @param _minLiquidity Minimum amount of assets to receive
     * @param _panic Set to true to ignore slippage when liquidating
     * @param _params Generic callData (e.g., SwapperParams)
     * @return liquidityAvailable Amount of assets available to liquidate
     */
    function liquidate(
        uint256[8] calldata _amounts,
        uint256 _minLiquidity,
        bool _panic,
        bytes[] memory _params
    )
        external
        onlyKeeper
        nonReentrant
        returns (uint256 liquidityAvailable)
    {
        // pre-liquidation sharePrice
        last.sharePrice = sharePrice();

        // In share
        uint256 pendingRedemption = totalPendingRedemptionRequest();

        // liquidate protocol positions
        uint256 liquidated = _liquidate(_amounts, _params);

        req.totalClaimableRedemption += pendingRedemption;

        // we use availableClaimable() and not availableBorrowable() to avoid intra-block cash variance (absorbed by the redemption claim delays)
        liquidityAvailable = availableClaimable().subMax0(req.totalClaimableRedemption.mulDiv(weiPerAsset, last.sharePrice));

        // check if we have enough cash to repay redemption requests
        if ((liquidityAvailable < _minLiquidity) && !_panic)
            revert AmountTooLow(liquidityAvailable);

        last.liquidate = uint64(block.timestamp);
        emit Liquidate(liquidated, liquidityAvailable, block.timestamp);
        return liquidityAvailable;
    }

    /**
     * @dev Internal function to liquidate a specified amount, to be implemented by strategies
     * @param _amount Amount to be liquidated
     * @return Amount that was liquidated
     */
    function _liquidateRequest(
        uint256 _amount
    ) internal virtual returns (uint256) {}

    /**
     * @notice Order the withdrawal request in strategies with lock
     * @param _amount Amount of debt to liquidate
     * @return assetsRecovered Amount of assets recovered
     */
    function liquidateRequest(
        uint256 _amount
    ) external onlyKeeper returns (uint256) {
        return _liquidateRequest(_amount);
    }

    /**
     * @dev Internal function to harvest rewards, to be implemented by strategies
     * @param _params Generic callData (e.g., SwapperParams)
     * @return amount Amount of asset assets received (after swap)
     */
    function _harvest(
        bytes[] memory _params
    ) internal virtual returns (uint256 amount) {}

    /**
     * @notice Harvest rewards from the protocol
     * @param _params Generic callData (e.g., SwapperParams)
     * @return amount Amount of asset assets received (after swap)
     */
    function harvest(bytes[] memory _params) public returns (uint256 amount) {
        amount = _harvest(_params);
        // reset expected profits to updated value + amount
        expectedProfits =
            AsAccounting.unrealizedProfits(
                last.harvest,
                expectedProfits,
                profitCooldown
            ) +
            amount;
        last.harvest = uint64(block.timestamp);
        emit Harvest(amount, block.timestamp);
    }

    /**
     * @notice Invests the asset asset into the pool
     * @param _amounts Amounts of asset to invest in each input
     * @param _params Swaps calldata
     * @return investedAmount Amount invested
     * @return iouReceived Amount of LP tokens received
     */
    function _invest(
        uint256[8] calldata _amounts, // from previewInvest()
        bytes[] memory _params
    ) internal virtual returns (uint256 investedAmount, uint256 iouReceived) {}

    /**
     * @notice Invests the asset asset into the pool
     * @param _amounts Amounts of asset to invest in each input
     * @param _params Swaps calldata
     * @return investedAmount Amount invested
     * @return iouReceived Amount of LP tokens received
     */
    function invest(
        uint256[8] calldata _amounts, // from previewInvest()
        bytes[] memory _params
    ) public onlyManager returns (uint256 investedAmount, uint256 iouReceived) {
        (investedAmount, iouReceived) = _invest(_amounts, _params);
        last.invest = uint64(block.timestamp);
        emit Invest(investedAmount, block.timestamp);
        return (investedAmount, iouReceived);
    }

    /**
     * @notice Compounds the strategy using SwapData for both harvest and invest
     * @dev Pass a conservative _amount (e.g., available() + 90% of rewards valued in asset)
     * to ensure the asset->inputs swaps
     * @param _amounts Amount of inputs to invest (in asset, after harvest-> should include rewards)
     * @param _params Generic callData (harvest+invest SwapperParams)
     * @return iouReceived IOUs received from the compound operation
     * @return harvestedRewards Amount of rewards harvested
     */
    function _compound(
        uint256[8] calldata _amounts,
        bytes[] memory _params // rewardTokens(0...n)->underling() / asset()->inputs(0...n) with assetWeights(0...n)
    ) internal virtual returns (uint256 iouReceived, uint256 harvestedRewards) {
        // we expect the SwapData to cover harvesting + investing
        if (_params.length != (rewardLength + inputLength))
            revert InvalidCalldata();

        // harvest using the first calldata bytes (swap rewards->asset)
        harvestedRewards = harvest(_params.slice(0, rewardLength));
        (, iouReceived) = _invest(
            _amounts,
            _params.slice(rewardLength, _params.length)
        ); // invest using the second calldata bytes (swap asset->inputs)
        return (iouReceived, harvestedRewards);
    }

    /**
     * @notice Executes the compound operation in the strategy
     * @param _amounts Amounts of inputs to compound (in asset, after harvest-> should include rewards)
     * @param _params Generic callData for the compound operation
     * @return iouReceived IOUs received from the compound operation
     * @return harvestedRewards Amount of rewards harvested
     */
    function compound(
        uint256[8] calldata _amounts,
        bytes[] memory _params
    )
        external
        onlyKeeper
        returns (uint256 iouReceived, uint256 harvestedRewards)
    {
        (iouReceived, harvestedRewards) = _compound(_amounts, _params);
        emit Compound(iouReceived, block.timestamp);
    }

    /**
     * @dev Internal virtual function to set allowances, to be implemented by specific strategies
     * @param _amount Amount for which to set the allowances
     */
    function _setAllowances(uint256 _amount) internal virtual {}

    /**
     * @notice Converts asset wei amount to input wei amount
     * @return Input amount in wei
     * @dev Abstract function to be implemented by the oracle or the strategy
     */
    function _assetToInput(
        uint256 _amount,
        uint8 _index
    ) internal view virtual returns (uint256) {}

    /**
     * @notice Converts input wei amount to asset wei amount
     * @return Asset amount in wei
     * @dev Abstract function to be implemented by the oracle or the strategy
     */
    function _inputToAsset(
        uint256 _amount,
        uint8 _index
    ) internal view virtual returns (uint256) {}

    /**
     * @notice Convert LP/staked LP to input
     * @return Input value of the LP amount
     * @dev Abstract function to be implemented by the oracle or the strategy
     */
    function _stakeToInput(
        uint256 _amount,
        uint8 _index
    ) internal view virtual returns (uint256) {}

    /**
     * @notice Convert input to LP/staked LP
     * @return LP value of the input amount
     * @dev Abstract function to be implemented by the oracle or the strategy
     */
    function _inputToStake(
        uint256 _amount,
        uint8 _index
    ) internal view virtual returns (uint256) {}

    /**
     * @notice Returns the invested input converted from the staked LP token
     * @return Input value of the LP/staked balance
     * @dev Abstract function to be implemented by the oracle or the strategy
     */
    function _stakedInput(
        uint8 _index
    ) internal view virtual returns (uint256) {}

    /**
     * @notice Amount of _index input denominated in asset
     * @dev Abstract function to be implemented by the strategy
     * @param _index Index of the asset
     * @return Amount of assets
     */
    function invested(uint8 _index) public view virtual returns (uint256) {}

    /**
     * @notice Amount of _index input
     * @dev Abstract function to be implemented by the strategy
     * @param _index Index of the asset
     * @return Amount of assets
     */
    function investedInput(uint8 _index) internal view virtual returns (uint256) {}

    /**
     * @notice Returns the investment in asset asset
     * @return total Amount invested
     */
    function invested() public view virtual override returns (uint256 total) {
        for (uint8 i = 0; i < inputLength; i++)
            total += invested(i);
    }

    /**
     * @notice Convert LP/staked LP to input
     * @return Input value of the LP amount
     */
    function _stakeToAsset(
        uint256 _amount,
        uint8 _index
    ) internal view returns (uint256) {
        return _inputToAsset(_stakeToInput(_amount, _index), _index);
    }

    /**
     * @notice Convert asset to LP/staked LP
     * @return LP value of the asset amount
     */
    function _assetToStake(
        uint256 _amount,
        uint8 _index
    ) internal view returns (uint256) {
        return _inputToStake(_assetToInput(_amount, _index), _index);
    }

    /**
     * @dev Calculate the excess weight for a given input index
     * @param _index Index of the input
     * @param _total Total invested amount
     * @return int256 Excess weight (/AsMaths.BP_BASIS)
     */
    function _excessWeight(
        uint8 _index,
        uint256 _total
    ) internal view returns (int256) {
        if (_total == 0) _total = invested();
        return
            int256(invested(_index).mulDiv(AsMaths.BP_BASIS, _total)) -
            int256(uint256(inputWeights[_index]));
    }

    /**
     * @dev Calculate the excess weights for all inputs
     * @param _total Total invested amount
     * @return excessWeights int256[8] Excess weights for each input
     */
    function _excessWeights(
        uint256 _total
    ) internal view returns (int256[8] memory excessWeights) {
        if (_total == 0) _total = invested();
        for (uint8 i = 0; i < inputLength; i++)
            excessWeights[i] = _excessWeight(i, _total);
    }

    /**
     * @dev Calculate the excess liquidity for a given input
     * @param _index Index of the input
     * @param _total Total invested amount in asset (0 == invested())
     * @return int256 Excess liquidity
     */
    function _excessInputLiquidity(
        uint8 _index,
        uint256 _total
    ) internal view returns (int256) {
        if (_total == 0) _total = invested();
        return
            int256(investedInput(_index)) -
            int256(_assetToInput(_total.mulDiv(uint256(inputWeights[_index]), AsMaths.BP_BASIS), _index));
    }

    /**
     * @dev Calculate the excess liquidity for all inputs
     * @param _total Total invested amount in asset (0 == invested())
     * @return excessLiquidity int256[8] Excess liquidity for each input
     */
    function _excessInputLiquidity(
        uint256 _total
    ) internal view returns (int256[8] memory excessLiquidity) {
        if (_total == 0) _total = invested();
        for (uint8 i = 0; i < inputLength; i++)
            excessLiquidity[i] = _excessInputLiquidity(i, _total);
    }

    /**
     * @dev Preview the amounts that would be liquidated based on the given amount
     * @param _amount Amount of asset to liquidate with (0 == totalPendingAssetRequest() + allocated.bp(100))
     * @return amounts uint256[8] Previewed liquidation amounts for each input
     */
    function previewLiquidate(
        uint256 _amount
    ) public view returns (uint256[8] memory amounts) {
        uint256 allocated = invested();
        _amount += AsMaths.min(totalPendingAssetRequest() + allocated.bp(100), allocated); // defaults to requests + 1% offset to buffer flows
        // excessInput accounts for the weights and the cash available in the strategy
        int256[8] memory excessInput = _excessInputLiquidity(allocated - _amount);
        for (uint8 i = 0; i < inputLength; i++) {
            if (_amount < 10) break; // no leftover
            if (excessInput[i] > 0) {
                uint256 need = _inputToAsset(excessInput[i].abs(), i);
                if (need > _amount)
                    need = _amount;
                amounts[i] = _assetToInput(need, i);
                _amount -= need;
            }
        }
    }

    /**
     * @dev Preview the amounts that would be invested based on the given amount
     * @param _amount Amount of asset to invest with
     * @return amounts uint256[8] Previewed investment amounts for each input in asset
     */
    function previewInvest(
        uint256 _amount
    ) public view returns (uint256[8] memory amounts) {
        if (_amount == 0)
            _amount = available(); // only invest 90% of liquidity for buffered flows
        int256[8] memory excessInput = _excessInputLiquidity(invested() + _amount);
        for (uint8 i = 0; i < inputLength; i++) {
            if (_amount < 10) break; // no leftover
            if (excessInput[i] < 0) {
                uint256 need = _inputToAsset(excessInput[i].abs(), i);
                if (need > _amount)
                    need = _amount;
                amounts[i] = need;
                _amount -= need;
            }
        }
    }

    /**
     * @dev IERC165-supportsInterface
     */
    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return interfaceId == type(IStrategyV5).interfaceId;
    }

    /**
     * @notice Amount of rewards available to harvest
     * @dev Abstract function to be implemented by the strategy
     * @return amounts Amount of reward tokens available
     */
    function rewardsAvailable()
        public
        view
        virtual
        returns (uint256[] memory amounts)
    {}

    /**
     * @dev Wraps the contract full native balance (the contract does not need gas)
     * @return amount of native asset wrapped
     */
    function _wrapNative() internal virtual returns (uint256 amount) {
        if (address(asset) == address(0)) {
            amount = address(this).balance;
            if (amount > 0)
                IWETH9(wgas).deposit{value: amount}();
        }
    }

    /**
     * @dev Returns the total token balance of the contract (native+wrapped native if token == address(1))
     * @return The total balance of the contract
     */
    function _balance(address token) internal view virtual returns (uint256) {
        return (token == address(1) || token == address(wgas)) ?
            address(this).balance + wgas.balanceOf(address(this)) :
            IERC20(token).balanceOf(address(this));
    }
}
