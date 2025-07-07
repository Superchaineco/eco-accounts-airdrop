// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Script, console} from "forge-std/Script.sol";
import {ProsperityAidrop} from "../src/ProsperityAirdrop.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SetMerkleRoot is Script {
    bytes32 private _merkleRoot =
        0x3546c721dfc9bf02a2f10b38c64b7ba6c6d3217afaba535e3ecbb59d0e0c8612;
    // uint256 private _amount = 2500000 * 4 * 1e18;
    // Expiration time: 30 days from now (in seconds)
    uint256 private _expirationTime = block.timestamp + 30 days;

    function run() public returns (ProsperityAidrop) {
        vm.startBroadcast();
        ProsperityAidrop airdrop = ProsperityAidrop(
            0xcc86F7903f52EEb20c512D26C829e1545D577c47
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
