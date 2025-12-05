// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockStablecoin
 * @dev Mock ERC20 token for testnet
 */
contract MockStablecoin is ERC20, Ownable {
    uint8 private immutable _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimalsValue
    ) ERC20(name, symbol) Ownable(msg.sender) {
        _decimals = decimalsValue;
        // Mint initial supply to deployer
        _mint(msg.sender, 1_000_000 * 10**decimalsValue);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    /**
     * @dev Public faucet for testing - anyone can get tokens
     * Mints 10,000 tokens to the caller
     */
    function faucet() external {
        uint256 amount = 10_000 * 10**uint256(_decimals);
        _mint(msg.sender, amount);
    }

    function batchMint(address[] calldata recipients, uint256 amount) external onlyOwner {
        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amount);
        }
    }
}
