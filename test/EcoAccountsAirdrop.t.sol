// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import {Test, console} from "forge-std/Test.sol";
import {EcoAccountsAirdrop} from "../src/EcoAccountsAirdrop.sol";
import {DeployAirdrop} from "../script/DeployAirdrop.s.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

contract MerkleAirdropTest is Test {
    EcoAccountsAirdrop public airdrop;
    MockToken public token;
    uint256 public amount = 25 * 1e18;
    bytes32 public merkleRoot =
        0x91673d887a585a027b96f72ced7bdc3c67fd0725fbd74fe1c8e1cba3b6419681;
    bytes32 ZERO_PROOF =
        0x0000000000000000000000000000000000000000000000000000000000000000;
    bytes32 PROOF_1 =
        0x861d0a93c670f720d1a5c8f5115256bc24af1ef30806723ebb4080a9c4f67da6;
    bytes32 PROOF_2 =
        0xd65d69953c587119b1322acd3c1c33c17d3c974779ce01557e3e2d80dd35c3ff;
    bytes32 PROOF_3 =
        0xbe57b94b9436f8262e32c2b0b5192a73d2c35249f40d9c8da40f6ed5704a9a0b;
    bytes32 PROOF_4 =
        0x3afdce198a34f39f114f7f427c224022480b23fe2cf42d7dff2d360704ec960d;
    bytes32 PROOF_5 =
        0x1adc11ebe608cd68f9448fa1bf3697658ba03a0f0644ca7ab4d269c8776c752f;
    bytes32 PROOF_6 =
        0x2ba4dab4a872577d7a40bfe1a74ce078ec0105bbab0115ed01d86b14c4c2b529;
    bytes32[] internal PROOF = [
        PROOF_1,
        ZERO_PROOF,
        PROOF_2,
        ZERO_PROOF,
        PROOF_3,
        ZERO_PROOF,
        ZERO_PROOF,
        ZERO_PROOF,
        PROOF_4,
        ZERO_PROOF,
        ZERO_PROOF,
        ZERO_PROOF,
        PROOF_5,
        ZERO_PROOF,
        ZERO_PROOF,
        PROOF_6
    ];
    address user;
    uint256 userPk;

    address admin;
    uint256 adminPk;

    function setUp() public {
        (user, userPk) = makeAddrAndKey("User");
        (admin, adminPk) = makeAddrAndKey("Admin");
        DeployAirdrop deploy = new DeployAirdrop();
        (airdrop, token) = deploy.deployAirdrop();
    }

    function testUserClaim() public {
        uint256 startingBalance = token.balanceOf(user);
        console.log("Starting Balance: %s", startingBalance);

        vm.prank(user);
        airdrop.claimERC20(address(token), user, amount, 1, PROOF);

        uint256 endingBalance = token.balanceOf(user);
        console.log("Ending Balance: %s", endingBalance);

        assertEq(endingBalance - startingBalance, amount);
    }

    function testUserClaimTwice() public {
        testUserClaim();
        vm.prank(user);
        vm.expectRevert();
        airdrop.claimERC20(address(token), user, amount, 1, PROOF);
    }

    function testAirdropExpiration() public {
        // Set expiration time to 1 hour from now
        uint256 expirationTime = block.timestamp + 1 hours;

        DeployAirdrop deploy = new DeployAirdrop();
        (airdrop, token) = deploy.deployAirdrop(
            amount,
            merkleRoot,
            expirationTime
        );

        // Verify expiration time is set correctly
        assertEq(
            airdrop.tokenExpirationTime(address(token), 1),
            expirationTime
        );

        // Verify airdrop is not expired initially
        assertFalse(airdrop.isAirdropExpired(address(token), 1));

        // Claim should work before expiration
        vm.prank(user);
        airdrop.claimERC20(address(token), user, amount, 1, PROOF);

        // Fast forward time to after expiration
        vm.warp(expirationTime + 1);

        // Verify airdrop is now expired
        assertTrue(airdrop.isAirdropExpired(address(token), 1));
    }

    function testCannotClaimAfterExpiration() public {
        // Set expiration time to 1 hour from now
        uint256 expirationTime = block.timestamp + 1 hours;

        DeployAirdrop deploy = new DeployAirdrop();
        (airdrop, token) = deploy.deployAirdrop(
            amount,
            merkleRoot,
            expirationTime
        );

        // Fast forward time to after expiration
        vm.warp(expirationTime + 1);

        // Claim should fail after expiration
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(EcoAccountsAirdrop.AirdropExpired.selector)
        );
        airdrop.claimERC20(address(token), user, amount, 1, PROOF);
    }

    function testUpdateExpiration() public {
        // Set initial expiration time
        uint256 initialExpiration = block.timestamp + 1 hours;
        MockToken localToken = new MockToken();
        EcoAccountsAirdrop localAirdrop = new EcoAccountsAirdrop();
        localAirdrop.setMerkleRoot(
            address(localToken),
            merkleRoot,
            true,
            initialExpiration
        );
        localToken.mint(localAirdrop.owner(), amount);
        localToken.approve(address(localAirdrop), amount);

        // Update expiration time
        uint256 newExpiration = block.timestamp + 2 hours;
        localAirdrop.updateAirdropExpiration(
            address(localToken),
            1,
            newExpiration
        );

        // Verify new expiration time
        assertEq(
            localAirdrop.tokenExpirationTime(address(localToken), 1),
            newExpiration
        );

        // Fast forward past initial expiration but before new expiration
        vm.warp(initialExpiration + 30 minutes);

        // Claim should still work
        vm.prank(user);
        localAirdrop.claimERC20(address(localToken), user, amount, 1, PROOF);
    }

    function testNoExpirationByDefault() public {
        // Set merkle root without expiration (0 means no expiration)
        DeployAirdrop deploy = new DeployAirdrop();
        (airdrop, token) = deploy.deployAirdrop(amount, merkleRoot, 0);

        // Verify no expiration is set
        assertEq(airdrop.tokenExpirationTime(address(token), 1), 0);
        assertFalse(airdrop.isAirdropExpired(address(token), 1));

        // Fast forward time significantly
        vm.warp(block.timestamp + 365 days);

        // Airdrop should still not be expired
        assertFalse(airdrop.isAirdropExpired(address(token), 1));

        // Claim should still work
        vm.prank(user);
        airdrop.claimERC20(address(token), user, amount, 1, PROOF);
    }

    function testMultipleAirdropsSameToken() public {
        // First airdrop
        vm.prank(airdrop.owner());
        airdrop.setMerkleRoot(address(token), merkleRoot, true, 0);
        uint256 conditionId1 = airdrop.tokenConditionId(address(token));

        // Claim first airdrop
        vm.prank(user);
        airdrop.claimERC20(address(token), user, amount, conditionId1, PROOF);

        uint256 balanceAfterFirst = token.balanceOf(user);
        assertEq(balanceAfterFirst, amount);

        // Second airdrop with same merkle root
        vm.prank(airdrop.owner());
        airdrop.setMerkleRoot(address(token), merkleRoot, true, 0);
        uint256 conditionId2 = airdrop.tokenConditionId(address(token));

        // Claim second airdrop
        vm.prank(user);
        airdrop.claimERC20(address(token), user, amount, conditionId2, PROOF);

        uint256 balanceAfterSecond = token.balanceOf(user);
        assertEq(balanceAfterSecond, amount * 2);
    }
}
