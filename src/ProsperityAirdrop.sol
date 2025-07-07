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

contract ProsperityAidrop is EIP712, Ownable {
    /*///////////////////////////////////////////////////////////////
                            State, constants & structs
    //////////////////////////////////////////////////////////////*/

    /// @dev token contract address => conditionId
    mapping(address => uint256) public tokenConditionId;
    /// @dev token contract address => merkle root
    mapping(address => bytes32) public tokenMerkleRoot;
    /// @dev token contract address => expiration timestamp
    mapping(address => uint256) public tokenExpirationTime;
    /// @dev conditionId => hash(claimer address, token address, token id [1155]) => has claimed
    mapping(uint256 => mapping(bytes32 => bool)) private claimed;
    /// @dev Mapping from request UID => whether the request is processed.
    mapping(bytes32 => bool) public processed;

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

    /*///////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    event Airdrop(address token);
    event AirdropClaimed(address token, address receiver);
    event AirdropExpirationSet(address token, uint256 expirationTime);

    /*///////////////////////////////////////////////////////////////
                            Constructor
    //////////////////////////////////////////////////////////////*/

    constructor() Ownable(msg.sender) {}

    /*///////////////////////////////////////////////////////////////
                            Airdrop Push
    //////////////////////////////////////////////////////////////*/

    /**
     *  @notice          Lets contract-owner send native token (eth) to a list of addresses.
     *  @dev             Owner should send total airdrop amount as msg.value.
     *                   Can only be called by contract owner.
     *
     *  @param _contents List containing recipients and amounts to airdrop
     */
    function airdropNativeToken(
        AirdropContentERC20[] calldata _contents
    ) external payable onlyOwner {
        uint256 len = _contents.length;
        uint256 nativeTokenAmount;

        for (uint256 i = 0; i < len; i++) {
            nativeTokenAmount += _contents[i].amount;
            SafeTransferLib.safeTransferETH(
                _contents[i].recipient,
                _contents[i].amount
            );
        }

        if (nativeTokenAmount != msg.value) {
            revert AirdropValueMismatch();
        }

        emit Airdrop(NATIVE_TOKEN_ADDRESS);
    }

    /**
     *  @notice          Lets contract owner send ERC20 tokens to a list of addresses.
     *  @dev             The token-owner should approve total airdrop amount to this contract.
     *                   Can only be called by contract owner.
     *
     *  @param _tokenAddress Address of the ERC20 token being airdropped
     *  @param _contents     List containing recipients and amounts to airdrop
     */
    function airdropERC20(
        address _tokenAddress,
        AirdropContentERC20[] calldata _contents
    ) external onlyOwner {
        uint256 len = _contents.length;

        for (uint256 i = 0; i < len; i++) {
            SafeTransferLib.safeTransferFrom(
                _tokenAddress,
                msg.sender,
                _contents[i].recipient,
                _contents[i].amount
            );
        }

        emit Airdrop(_tokenAddress);
    }

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
        bytes32[] calldata _proofs
    ) external {
        bytes32 claimHash = _getClaimHashERC20(_receiver, _token);
        uint256 conditionId = tokenConditionId[_token];

        if (claimed[conditionId][claimHash]) {
            revert AirdropAlreadyClaimed();
        }

        bytes32 _tokenMerkleRoot = tokenMerkleRoot[_token];
        if (_tokenMerkleRoot == bytes32(0)) {
            revert AirdropNoMerkleRoot();
        }

        uint256 expirationTime = tokenExpirationTime[_token];
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

        claimed[conditionId][claimHash] = true;

        SafeTransferLib.safeTransferFrom(_token, owner(), _receiver, _quantity);

        emit AirdropClaimed(_token, _receiver);
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
        tokenMerkleRoot[_token] = _tokenMerkleRoot;
        tokenExpirationTime[_token] = _expirationTime;

        emit AirdropExpirationSet(_token, _expirationTime);
    }

    /**
     *  @notice          Lets contract owner extend the expiration time of an airdrop.
     *
     *  @param _token             Address of airdrop token
     *  @param _expirationTime    New expiration timestamp (0 for no expiration)
     */
    function updateAirdropExpiration(
        address _token,
        uint256 _expirationTime
    ) external onlyOwner {
        tokenExpirationTime[_token] = _expirationTime;
        emit AirdropExpirationSet(_token, _expirationTime);
    }

    /**
     *  @notice          Check if an airdrop has expired.
     *
     *  @param _token    Address of airdrop token
     *  @return expired  True if the airdrop has expired, false otherwise
     */
    function isAirdropExpired(address _token) external view returns (bool) {
        uint256 expirationTime = tokenExpirationTime[_token];
        return expirationTime > 0 && block.timestamp > expirationTime;
    }

    /// @notice Returns claim status of a receiver for a claim based airdrop
    function isClaimed(
        address _receiver,
        address _token,
        uint256 _tokenId
    ) external view returns (bool) {
        uint256 _conditionId = tokenConditionId[_token];

        bytes32 claimHash = keccak256(
            abi.encodePacked(_receiver, _token, _tokenId)
        );
        if (claimed[_conditionId][claimHash]) {
            return true;
        }

        claimHash = keccak256(abi.encodePacked(_receiver, _token));
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
        name = "Airdrop";
        version = "1";
    }

    /// @dev Keccak256 hash of receiver and token addresses, for claim based airdrop status tracking
    function _getClaimHashERC20(
        address _receiver,
        address _token
    ) private view returns (bytes32) {
        return keccak256(abi.encodePacked(_receiver, _token));
    }
}
