// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/Proxy.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title AsProxy Abstract - EIP-897 delegate proxy (OpenZeppelin standard proxy extension)
 * @author Astrolab DAO
 * @dev Make sure all to match proxy/implementation slots when used for UUPS / transparent proxies
 */
abstract contract AsProxy is Proxy {

    // to match with the payable fallback (not necessary but pleases compiler)
    receive() external payable {}

    /**
     * @notice Delegate a call to an implementation contract using a function selector and calldata encoded parameters
     * @param _implementation The address of the implementation contract
     * @param _selector The function selector to delegate to (4 first bytes of the signature keccak)
     * @param _params The parameters to pass to the function
     */
    function _delegateToSelector(
        address _implementation,
        bytes4 _selector,
        bytes calldata _params
    ) internal {
        assembly {
            _selector := and(_selector, 0xffffffff) // clear selector bytes after 4
            let paramsSize := calldataload(_params.offset) // determine _params size from calldata
            let calldataSize := add(0x4, paramsSize) // total calldata size (selector + params)
            let callData := mload(0x40) // free ptr
            mstore(callData, _selector) // store selector in the first 4 bytes
            calldatacopy(add(callData, 0x4), _params.offset, paramsSize) // copy params after the selector in the new calldata
            mstore(0x40, add(callData, calldataSize)) // update free ptr
            let result := delegatecall(
                gas(),
                _implementation, // implementation address
                callData, // inputs
                calldataSize, // input size
                0, // output location
                0 // output size
            )
            let size := returndatasize() // return data size
            let ptr := mload(0x40) // free ptr
            returndatacopy(ptr, 0, size) // copy return data to free ptr
            mstore(0x40, add(ptr, size)) // update free ptr
            switch result
            case 0 {
                revert(ptr, size)
            }
            default {
                return(ptr, size)
            }
        }
    }

    /**
     * @notice Delegate a call to an implementation contract using a function selector and memory encoded parameters
     * @param _implementation The address of the implementation contract
     * @param _selector The function selector to delegate to (4 first bytes of the signature keccak)
     * @param _params The parameters to pass to the function
     */
    function _delegateToSelectorMemory(
        address _implementation,
        bytes4 _selector,
        bytes memory _params
    ) internal {
        assembly {
            _selector := and(_selector, 0xffffffff) // clear selector bytes after 4
            let paramsSize := mload(_params) // determine _params size from in-memory array
            let calldataSize := add(0x4, paramsSize) // total calldata size (selector + params)
            let callData := mload(0x40) // free ptr
            mstore(callData, _selector) // store selector in the first 4 bytes
            mstore(0x40, add(callData, calldataSize)) // copy the params to the free memory pointer (post size slot)
            let result := delegatecall(
                gas(),
                _implementation, // implementation address
                add(callData, 0x20), // inputs stored at callData + 0x20 (size slot)
                calldataSize, // input size
                0, // output location
                0  // output size
            )
            let size := returndatasize() // return data size
            let ptr := mload(0x40) // free ptr
            returndatacopy(ptr, 0, size) // copy return data to free ptr
            switch result
            case 0 {
                revert(ptr, size)
            }
            default {
                return(ptr, size)
            }
        }
    }

    /**
     * @dev Returns the EIP-897 address of the implementation contract
     * @return The address of the implementation contract
     */
    function implementation() external view virtual returns (address) {
        return _implementation();
    }

    /**
     * @dev Returns the EIP-897 proxy type
     * @return The proxy type
     */
    function proxyType() external pure virtual returns (uint256) {
        return 2;
    }
}
