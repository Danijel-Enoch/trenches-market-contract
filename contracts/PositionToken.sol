// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PositionToken is ERC20, Ownable {
    uint256 public immutable marketId;
    uint8 public immutable outcome;
    
    constructor(
        string memory name,
        string memory symbol,
        uint256 _marketId,
        uint8 _outcome,
        address _owner
    ) ERC20(name, symbol) Ownable(_owner) {
        marketId = _marketId;
        outcome = _outcome;
    }
    
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
    
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}
