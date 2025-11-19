// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Pixel is ERC20, ERC20Permit, ERC20Votes, Ownable {
    mapping(address => bool) public account_Minter;

    error Pixel__NotMinter();
    error Pixel__InvalidMinter();

    event Pixel__Minted(address indexed account, uint256 amount);
    event Pixel__Burned(address indexed account, uint256 amount);
    event Pixel__MinterUpdated(address indexed account, bool status);

    constructor() ERC20("Pixel", "PIXEL") ERC20Permit("Pixel") {}

    function setMinter(address account, bool status) external onlyOwner {
        if (account == address(0)) revert Pixel__InvalidMinter();
        account_Minter[account] = status;
        emit Pixel__MinterUpdated(account, status);
    }

    function mint(address account, uint256 amount) external {
        if (!account_Minter[msg.sender]) revert Pixel__NotMinter();
        _mint(account, amount);
        emit Pixel__Minted(account, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
        emit Pixel__Burned(msg.sender, amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }
}
