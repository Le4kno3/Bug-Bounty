// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FYGN is ERC20Burnable, Ownable {
    mapping(address => bool) public whitelistedMinters;

    modifier onlyWhitelistedMinter() {
        require(whitelistedMinters[msg.sender], "User not whitelisted");
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_
    ) public ERC20(name_, symbol_) {}

    function whitelistMinter(address _whitelistAddress) public onlyOwner {
        //@audit-issue - The check is either incorrect or the reason string is not correct. Otherwise the check is fine.
        require(_whitelistAddress != address(0), "Not owner");

        whitelistedMinters[_whitelistAddress] = true;
    }

    function mint(
        address account,
        uint256 amount
    ) external onlyWhitelistedMinter {
        //@audit-issue (Low) - No limit on number of tokens being minted, what if the whitelisted user goes rogue.
        _mint(account, amount);
    }
}
