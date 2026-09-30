// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockERC20
/// @notice Mintable ERC20 token used by the EscrowMarketplace test suite.
contract MockERC20 is ERC20 {
    /// @notice Deploys the mock token with a fixed name and symbol.
    constructor() ERC20("Mock Token", "MOCK") {}

    /// @notice Mints test tokens to an address without access restrictions.
    /// @param to Address receiving the minted tokens.
    /// @param amount Amount of tokens to mint.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
