// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.25;
import "@fhenixprotocol/cofhe-contracts/FHE.sol";

contract Metadata {
    mapping(uint256 => uint256) public metaMap;

    function addEuint8Metadata(InEuint8 memory in8) public {
        euint8 out = FHE.asEuint8(in8);
        metaMap[in8.ctHash] = euint8.unwrap(FHE.asEuint8(in8));
    }
    function addEuint16Metadata(InEuint16 memory in16) public {
        metaMap[in16.ctHash] = euint16.unwrap(FHE.asEuint16(in16));
    }
    function addEuint32Metadata(InEuint32 memory in32) public {
        metaMap[in32.ctHash] = euint32.unwrap(FHE.asEuint32(in32));
    }
    function addEuint64Metadata(InEuint64 memory in64) public {
        metaMap[in64.ctHash] = euint64.unwrap(FHE.asEuint64(in64));
    }
    function addEuint128Metadata(InEuint128 memory in128) public {
        metaMap[in128.ctHash] = euint128.unwrap(FHE.asEuint128(in128));
    }
    function addEuint256Metadata(InEuint256 memory in256) public {
        metaMap[in256.ctHash] = euint256.unwrap(FHE.asEuint256(in256));
    }
    function addEboolMetadata(InEbool memory inBool) public {
        metaMap[inBool.ctHash] = ebool.unwrap(FHE.asEbool(inBool));
    }
    function addEaddressMetadata(InEaddress memory inAddress) public {
        metaMap[inAddress.ctHash] = eaddress.unwrap(FHE.asEaddress(inAddress));
    }
}
