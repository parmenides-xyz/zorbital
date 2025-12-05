import { FheTypes } from "cofhejs/node";

// Reserve 2 bytes for metadata (clears last 2 bytes of 256-bit word)
const HASH_MASK_FOR_METADATA = (1n << 256n) - 1n - 0xffffn; // 0xffff = 2^16 - 1

// Reserve 1 byte for security zone (lowest byte)
const SECURITY_ZONE_MASK = 0xffn; // type(uint8).max

// 7-bit uint type mask
const UINT_TYPE_MASK = 0xff >> 1; // 0x7f

// 1-bit trivially encrypted flag (MSB of a byte)
const TRIVIALLY_ENCRYPTED_MASK = 0xff - UINT_TYPE_MASK; // 0x80

// uintType mask positioned in the second-to-last byte
const SHIFTED_TYPE_MASK = BigInt(UINT_TYPE_MASK) << 8n; // 0x7f00n

// Helper function to encode isTrivial + uintType into a byte
const getByteForTrivialAndType = (isTrivial: boolean, uintType: number): number => {
  return (isTrivial ? TRIVIALLY_ENCRYPTED_MASK : 0x00) | (uintType & UINT_TYPE_MASK);
};

// Main function to append metadata
export const appendMetadata = (
  preCtHash: bigint,
  securityZone: number,
  uintType: number,
  isTrivial: boolean,
): bigint => {
  const result = preCtHash & HASH_MASK_FOR_METADATA;

  // Emulate uint8(int8(securityZone)) in Solidity
  const securityZoneByte = BigInt(((securityZone << 24) >> 24) & 0xff);

  const metadata = (BigInt(getByteForTrivialAndType(isTrivial, uintType)) << 8n) | securityZoneByte;

  return result | metadata;
};

// Utility function that accepts an encrypted input
export const appendMetadataToInput = (encryptedInput: {
  ctHash: bigint;
  securityZone: number;
  utype: FheTypes;
}): bigint => {
  return appendMetadata(encryptedInput.ctHash, encryptedInput.securityZone, encryptedInput.utype, false);
};

// Extracts the signed int8 security zone from the lowest byte
export const getSecurityZoneFromHash = (hash: bigint): number => {
  const byte = Number(hash & SECURITY_ZONE_MASK);
  return (byte << 24) >> 24; // simulates int8 to int32
};

// Extracts the uintType from the second-to-last byte
export const getUintTypeFromHash = (hash: bigint): number => {
  return Number((hash & SHIFTED_TYPE_MASK) >> 8n);
};

// Extracts the 2-byte metadata (type + securityZone) from the hash
export const getSecAndTypeFromHash = (hash: bigint): bigint => {
  return hash & (SHIFTED_TYPE_MASK | SECURITY_ZONE_MASK);
};

// Checks if the trivially encrypted bit (bit 15) is set
export const isTriviallyEncryptedFromHash = (hash: bigint): boolean => {
  return (Number(hash) & TRIVIALLY_ENCRYPTED_MASK) === TRIVIALLY_ENCRYPTED_MASK;
};
