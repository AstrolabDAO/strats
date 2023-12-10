// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.0;

/**
 * @title Prevents delegatecall to a contract
 * @notice Abstract contract that provides a modifier for preventing delegatecalls in implementations
 */
abstract contract NoDelegate {

    address private immutable root;

    /**
     * @dev Initializes the root address.
     */
    constructor() {
        // Immutables are computed in the init code of the contract, and then inlined into the deployed bytecode.
        // In other words, this variable won't change when it's checked at runtime.
        root = address(this);
    }

    /**
     * @dev Private method is used instead of inlining into modifier because modifiers are copied into each method,
     *     and the use of immutable means the address bytes are copied in every place the modifier is used.
     */
    function checkNotDelegate() private view {
        require(address(this) == root);
    }

    /**
     * @notice Prevents delegatecall into the modified method
     */
    modifier noDelegate() {
        checkNotDelegate();
        _;
    }
}
