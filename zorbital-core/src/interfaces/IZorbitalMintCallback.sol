// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

interface IZorbitalMintCallback {
    function zorbitalMintCallback(
        uint256[] memory amounts,
        bytes calldata data
    ) external;
}
