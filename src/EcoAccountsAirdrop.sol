// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

import "solady/utils/MerkleProofLib.sol";
import "solady/utils/ECDSA.sol";
import "solady/utils/EIP712.sol";
import "solady/utils/SafeTransferLib.sol";
import "solady/utils/SignatureCheckerLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "forge-std/console.sol";

// @author Anotherdev
// @author Modified from Thirdweb

contract EcoAccountsAirdrop is EIP712, Ownable {
    /*///////////////////////////////////////////////////////////////
                            State, constants & structs
    //////////////////////////////////////////////////////////////*/

    /// @dev token contract address => conditionId
    mapping(address => uint256) public tokenConditionId;
    /// @dev token contract address => merkle root
    mapping(address => mapping(uint256 => bytes32)) public tokenMerkleRoot;
    /// @dev token contract address => expiration timestamp
    mapping(address => mapping(uint256 => uint256)) public tokenExpirationTime;
    /// @dev conditionId => hash(claimer address, token address, token id [1155]) => has claimed
    mapping(uint256 => mapping(bytes32 => bool)) private claimed;

    struct AirdropContentERC20 {
        address recipient;
        uint256 amount;
    }

    address private constant NATIVE_TOKEN_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /*///////////////////////////////////////////////////////////////
                                Errors
    //////////////////////////////////////////////////////////////*/

    error AirdropInvalidProof();
    error AirdropAlreadyClaimed();
    error AirdropNoMerkleRoot();
    error AirdropValueMismatch();
    error AirdropExpired();
    error InvalidConditionId();

    /*///////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    event AirdropClaimed(
        address indexed token,
        uint256 indexed tokenConditionId,
        address indexed receiver
    );
    event AirdropExpirationSet(
        address indexed token,
        uint256 indexed tokenConditionId,
        uint256 expirationTime
    );

    /*///////////////////////////////////////////////////////////////
                            Constructor
    //////////////////////////////////////////////////////////////*/

    constructor() Ownable(msg.sender) {}

    /*///////////////////////////////////////////////////////////////
                            Airdrop Claimable
    //////////////////////////////////////////////////////////////*/

    /**
     *  @notice          Lets allowlisted addresses claim ERC20 airdrop tokens.
     *  @dev             The token-owner should approve total airdrop amount to this contract,
     *                   and set merkle root of allowlisted address for this airdrop.
     *
     *  @param _token       Address of ERC20 airdrop token
     *  @param _receiver    Allowlisted address for which the token is being claimed
     *  @param _quantity    Allowlisted quantity of tokens to claim
     *  @param _proofs      Merkle proofs for allowlist verification
     */
    function claimERC20(
        address _token,
        address _receiver,
        uint256 _quantity,
        uint256 _conditionId,
        bytes32[] calldata _proofs
    ) external conditionIdGuard(_token, _conditionId) {
        bytes32 claimHash = _getClaimHashERC20(_receiver, _token);

        if (claimed[_conditionId][claimHash]) {
            revert AirdropAlreadyClaimed();
        }

        bytes32 _tokenMerkleRoot = tokenMerkleRoot[_token][_conditionId];
        if (_tokenMerkleRoot == bytes32(0)) {
            revert AirdropNoMerkleRoot();
        }

        uint256 expirationTime = tokenExpirationTime[_token][_conditionId];
        if (expirationTime > 0 && block.timestamp > expirationTime) {
            revert AirdropExpired();
        }

        bool valid = MerkleProofLib.verifyCalldata(
            _proofs,
            _tokenMerkleRoot,
            keccak256(bytes.concat(keccak256(abi.encode(_receiver, _quantity))))
        );
        if (!valid) {
            revert AirdropInvalidProof();
        }

        claimed[_conditionId][claimHash] = true;

        SafeTransferLib.safeTransferFrom(_token, owner(), _receiver, _quantity);

        emit AirdropClaimed(_token, _conditionId, _receiver);
    }

    /*///////////////////////////////////////////////////////////////
                            Setter functions
    //////////////////////////////////////////////////////////////*/

    /**
     *  @notice          Lets contract owner set merkle root (allowlist) for claim based airdrops.
     *
     *  @param _token             Address of airdrop token
     *  @param _tokenMerkleRoot   Merkle root of allowlist
     *  @param _resetClaimStatus  Reset claim status / amount claimed so far to zero for all recipients
     *  @param _expirationTime    Timestamp when the airdrop expires (0 for no expiration)
     */
    function setMerkleRoot(
        address _token,
        bytes32 _tokenMerkleRoot,
        bool _resetClaimStatus,
        uint256 _expirationTime
    ) external onlyOwner {
        if (_resetClaimStatus || tokenConditionId[_token] == 0) {
            tokenConditionId[_token] += 1;
        }

        uint256 _conditionId = tokenConditionId[_token];

        tokenMerkleRoot[_token][_conditionId] = _tokenMerkleRoot;
        tokenExpirationTime[_token][_conditionId] = _expirationTime;

        emit AirdropExpirationSet(_token, _conditionId, _expirationTime);
    }

    /**
     *  @notice          Lets contract owner extend the expiration time of an airdrop.
     *
     *  @param _token             Address of airdrop token
     *  @param _expirationTime    New expiration timestamp (0 for no expiration)
     */
    function updateAirdropExpiration(
        address _token,
        uint256 _conditionId,
        uint256 _expirationTime
    ) external onlyOwner conditionIdGuard(_token, _conditionId) {
        tokenExpirationTime[_token][_conditionId] = _expirationTime;
        emit AirdropExpirationSet(_token, _conditionId, _expirationTime);
    }

    /**
     *  @notice          Check if an airdrop has expired.
     *
     *  @param _token    Address of airdrop token
     *  @return expired  True if the airdrop has expired, false otherwise
     */
    function isAirdropExpired(
        address _token,
        uint256 _conditionId
    ) external view returns (bool) {
        uint256 expirationTime = tokenExpirationTime[_token][_conditionId];
        return expirationTime > 0 && block.timestamp > expirationTime;
    }

    /// @notice Returns claim status of a receiver for a claim based airdrop
    function isClaimed(
        address _receiver,
        address _token,
        uint256 _conditionId
    ) external view returns (bool) {
        bytes32 claimHash = keccak256(abi.encodePacked(_receiver, _token));
        if (claimed[_conditionId][claimHash]) {
            return true;
        }

        return false;
    }

    /// @dev Domain name and version for EIP-712
    function _domainNameAndVersion()
        internal
        pure
        override
        returns (string memory name, string memory version)
    {
        name = "EcoAccountsAirdrop";
        version = "1";
    }

    /// @dev Keccak256 hash of receiver and token addresses, for claim based airdrop status tracking
    function _getClaimHashERC20(
        address _receiver,
        address _token
    ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(_receiver, _token));
    }

    modifier conditionIdGuard(address _token, uint256 _conditionId) {
        if (tokenConditionId[_token] < _conditionId) {
            revert InvalidConditionId();
        }
        _;
    }
}
