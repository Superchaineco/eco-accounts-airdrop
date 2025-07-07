// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Script, console} from "forge-std/Script.sol";
import {ProsperityAidrop} from "../src/ProsperityAirdrop.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

contract DeployAirdrop is Script {
    bytes32 private _merkleRoot =
        0x91673d887a585a027b96f72ced7bdc3c67fd0725fbd74fe1c8e1cba3b6419681;
    uint256 private _amount = 2500000 * 4 * 1e18;

    function deployAirdrop(
        uint256 _amount,
        bytes32 _merkleRoot,
        uint256 _expirationTime
    ) public returns (ProsperityAidrop, MockToken) {
        MockToken token = new MockToken();
        ProsperityAidrop airdrop = new ProsperityAidrop();
        airdrop.setMerkleRoot(
            address(token),
            _merkleRoot,
            true,
            _expirationTime
        );
        token.mint(airdrop.owner(), _amount);
        token.approve(address(airdrop), _amount);
        console.log("Merkle Airdrop deployed at %s", address(airdrop));
        return (airdrop, token);
    }

    function deployAirdrop() public returns (ProsperityAidrop, MockToken) {
        MockToken token = new MockToken();
        ProsperityAidrop airdrop = new ProsperityAidrop();
        airdrop.setMerkleRoot(address(token), _merkleRoot, true, 0);
        token.mint(airdrop.owner(), _amount);
        token.approve(address(airdrop), _amount);
        console.log("Merkle Airdrop deployed at %s", address(airdrop));
        return (airdrop, token);
    }

    function run() public {
        vm.startBroadcast();
        deployAirdrop();
        vm.stopBroadcast();
    }
}
