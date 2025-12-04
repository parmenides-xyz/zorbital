// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IOrbitalFlashCallback {
    function orbitalFlashCallback(bytes calldata data) external;
}
