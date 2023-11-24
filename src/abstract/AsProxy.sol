// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.6.0) (proxy/Proxy.sol)

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/Proxy.sol";

abstract contract AsProxy is Proxy {

    function _delegateWithSignature(address implementation, string memory signature) internal {
        bytes4 selector = bytes4(keccak256(bytes(signature)));
        assembly {
            // Store selector at the beginning of the calldata
            mstore(0x0, selector)
            // Copy the rest of calldata (skipping the first 4 bytes of the original function signature)
            calldatacopy(0x4, 0x4, sub(calldatasize(), 0x4))
            let result := delegatecall(gas(), implementation, 0x0, add(calldatasize(), 0x4), 0, 0)
            let size := returndatasize()
            let ptr := mload(0x40)
            returndatacopy(ptr, 0, size)

            switch result
            case 0 { revert(ptr, size) }
            default { return(ptr, size) }
        }
    }
}
