// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDC
/// @notice Testnet-only USDC stand-in. `mint` is public on purpose so a Fuji
///         demo can fund wallets without a faucet. Do not deploy this token
///         on Avalanche mainnet and do not point production accounting at it.
contract MockUSDC is ERC20 {
    constructor() ERC20("Test USDC", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Anyone may mint. This is the testnet faucet.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
