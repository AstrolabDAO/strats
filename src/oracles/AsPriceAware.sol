// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../interfaces/IPriceProvider.sol";
import "../access-control/AsPermissioned.sol";

/**
 *             _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2024
 *
 * @title AsPriceAware Abstract - Data consumer for price aware contracts
 * @author Astrolab DAO
 * @notice Extending this contract allows for price feed consumption
 */
abstract contract AsPriceAware is AsPermissioned {

  /*═══════════════════════════════════════════════════════════════╗
  ║                            STRUCTS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  struct PriceAwareStorage {
    IPriceProvider oracle;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                           CONSTANTS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  // EIP-7201 keccak256(abi.encode(uint256(keccak256("AsPriceAware.main")) - 1)) & ~bytes32(uint256(0xff));
  bytes32 private constant _STORAGE_SLOT =
    0xbb12abea6d8b08b111bc540c50c61a89c6948c27ba2a9f019b29f0ec7e3b3200;

  /*═══════════════════════════════════════════════════════════════╗
  ║                         INITIALIZERS                           ║
  ╚═══════════════════════════════════════════════════════════════*/

  constructor() {}

  /*═══════════════════════════════════════════════════════════════╗
  ║                           MODIFIERS                            ║
  ╚═══════════════════════════════════════════════════════════════*/

  modifier whenPriceAware() {
    if (address(_priceAwareStorage().oracle) == address(0)) {
      revert Errors.MissingOracle();
    }
    _;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                             VIEWS                              ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @return $ Upgradable EIP-7201 storage slot
   */
  function _priceAwareStorage() internal pure returns (PriceAwareStorage storage $) {
    assembly {
      $.slot := _STORAGE_SLOT
    }
  }

  /**
   * @return Oracle implementation address
   */
  function oracle() public view returns (IPriceProvider) {
    return _priceAwareStorage().oracle;
  }

  /*═══════════════════════════════════════════════════════════════╗
  ║                            SETTERS                             ║
  ╚═══════════════════════════════════════════════════════════════*/

  /**
   * @notice Sets the strategy price oracle implementation
   * @param _oracle Price provider instance address
   */
  function _updateOracle(address _oracle) internal {
    if (_oracle == address(0)) {
      revert Errors.AddressZero();
    }
    (bool success,) = _oracle.staticcall(
      abi.encodeWithSelector(IPriceProvider.hasFeed.selector, address(0))
    );
    if (!success) {
      revert Errors.ContractNonCompliant();
    }
    _priceAwareStorage().oracle = IPriceProvider(_oracle);
  }

  /**
   * @notice Sets the strategy price oracle implementation
   * @param _oracle Price provider instance address
   */
  function updateOracle(address _oracle) external onlyAdmin {
    _updateOracle(_oracle);
  }
}
