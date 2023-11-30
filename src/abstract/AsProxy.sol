// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/Proxy.sol";

/**            _             _       _
 *    __ _ ___| |_ _ __ ___ | | __ _| |__
 *   /  ` / __|  _| '__/   \| |/  ` | '  \
 *  |  O  \__ \ |_| | |  O  | |  O  |  O  |
 *   \__,_|___/.__|_|  \___/|_|\__,_|_.__/  ©️ 2023
 *
 * @title AsProxy Abstract - OpenZeppelin standard proxy extension
 * @author Astrolab DAO
 * @dev Make sure all to match proxy/implementation slots when used for UUPS / transparent proxies
 */
abstract contract AsProxy is Proxy {
    /**
     * @notice Delegate a call to an implementation contract using a function signature
     * @param implementation The address of the implementation contract
     * @param signature The function signature to delegate
     */
    function _delegateWithSignature(
        address implementation,
        string memory signature
    ) internal {
        bytes4 selector = bytes4(keccak256(bytes(signature)));
        assembly {
            // Store selector at the beginning of the calldata
            mstore(0x0, selector)
            // Copy the rest of calldata (skipping the first 4 bytes of the original function signature)
            calldatacopy(0x4, 0x4, sub(calldatasize(), 0x4))
            let result := delegatecall(
                gas(),
                implementation,
                0x0,
                add(calldatasize(), 0x4),
                0,
                0
            )
            let size := returndatasize()
            let ptr := mload(0x40)
            returndatacopy(ptr, 0, size)

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
     * @notice Returns the proxy initialization state
     */
    function initialized() public view virtual returns (bool) {
        return _implementation() != address(0);
    }
}
