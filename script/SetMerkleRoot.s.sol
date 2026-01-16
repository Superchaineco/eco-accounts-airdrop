// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Script, console} from "forge-std/Script.sol";
import {EcoAccountsAirdrop} from "../src/EcoAccountsAirdrop.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SetMerkleRoot is Script {
    bytes32 private _merkleRoot =
        0x7fbf015ed2fc29c6fa19c5b82443be5547608ae2823a40881b496f3ae07dc976;
    // uint256 private _amount = 2500000 * 4 * 1e18;
    // Expiration time: 30 days from now (in seconds)
    uint256 private _expirationTime = block.timestamp + 31 days;

    function run() public returns (EcoAccountsAirdrop) {
        vm.startBroadcast();
        EcoAccountsAirdrop airdrop = EcoAccountsAirdrop(
            0x2a4871972Ece4e6E04a07E0F3e3D8168a261Dce2
        );
        ERC20 CELO = ERC20(0x471EcE3750Da237f93B8E339c536989b8978a438);
        airdrop.setMerkleRoot(
            address(CELO),
            _merkleRoot,
            true,
            _expirationTime
        );
        console.log("Merkle root set at %s", address(airdrop));
        console.log("Expiration time set to %s", _expirationTime);
        vm.stopBroadcast();
        return airdrop;
    }
}
