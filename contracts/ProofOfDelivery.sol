// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IAccessRegistry {
    enum Role { None, Admin, FleetOwner, Carrier, ThirdPartyLogistics, Customer }
    function hasRole(address account, Role role) external view returns (bool);
}
interface IDeliveryManagement {
    function markDeliveredFromPoD(uint256 orderId) external;
    function getAssignedCarrier(uint256 orderId) external view returns (address);
}
interface IPaymentEscrow {
    function releasePayment(uint256 orderId) external;
}

/// @title ProofOfDeliverySig
/// @notice Proof-of-delivery storage + EIP-712 finalize (meta-tx). Minimal read helpers added.
contract ProofOfDeliverySig {
    /* --------------------------- Errors --------------------------- */
    error NotAuthorized();
    error InvalidInput(string);
    error ProofNotInit();
    error AlreadyFinalized();
    error SignatureExpired();
    error BadSigner();
    error LengthMismatch();

    /* --------------------------- Types --------------------------- */
    struct Checkpoint { int32 latE6; int32 lonE6; uint40 time; }
    struct Proof { bool exists; bool finalized; Checkpoint[] checkpoints; }

    /* --------------------------- State --------------------------- */
    IAccessRegistry public immutable registry;
    IDeliveryManagement public immutable delivery;
    IPaymentEscrow public immutable escrow;
    address public owner;

    mapping(uint256 => Proof) private _proofs;
    mapping(uint256 => uint256) public nonces; // per-order nonce for replay protection

    /* --------------------------- EIP-712 --------------------------- */
    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant FINALIZE_TYPEHASH =
        keccak256("Finalize(uint256 orderId,address payee,uint256 nonce,uint256 deadline)");

    /* --------------------------- Events --------------------------- */
    event ProofInitialized(uint256 indexed orderId, address indexed by);
    event CheckpointAdded(uint256 indexed orderId, int32 latE6, int32 lonE6, uint40 time, address indexed by);
    event Finalized(uint256 indexed orderId, uint256 time, address indexed by, address indexed signer);
    event OwnerTransferred(address indexed oldOwner, address indexed newOwner);

    /* --------------------------- Modifiers --------------------------- */
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotAuthorized();
        _;
    }

    constructor(
        address accessRegistry,
        address deliveryContract,
        address escrowContract,
        string memory name,
        string memory version
    ) {
        require(accessRegistry != address(0) && deliveryContract != address(0) && escrowContract != address(0), "zero addr");
        registry = IAccessRegistry(accessRegistry);
        delivery = IDeliveryManagement(deliveryContract);
        escrow = IPaymentEscrow(escrowContract);
        owner = msg.sender;

        uint256 chainId;
        assembly { chainId := chainid() }
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name)),
            keccak256(bytes(version)),
            chainId,
            address(this)
        ));
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero addr");
        emit OwnerTransferred(owner, newOwner);
        owner = newOwner;
    }

    function _isUpdater(address a) internal view returns (bool) {
        return registry.hasRole(a, IAccessRegistry.Role.Admin)
            || registry.hasRole(a, IAccessRegistry.Role.FleetOwner)
            || registry.hasRole(a, IAccessRegistry.Role.Carrier)
            || a == owner;
    }

    /* --------------------------- Proof lifecycle --------------------------- */

    /// @notice Initialize empty proof for order
    function initProof(uint256 orderId) external {
        if (orderId == 0) revert InvalidInput("orderId==0");
        Proof storage p = _proofs[orderId];
        if (p.exists) revert InvalidInput("exists");
        p.exists = true;
        p.finalized = false;
        emit ProofInitialized(orderId, msg.sender);
    }

    /// @notice Create proof and upload multiple checkpoints at once
    function createProofWithCheckpoints(
        uint256 orderId,
        int256[] calldata latE6s,
        int256[] calldata lonE6s,
        uint256[] calldata ts
    ) external {
        if (!_isUpdater(msg.sender)) revert NotAuthorized();
        if (orderId == 0) revert InvalidInput("orderId==0");

        uint256 len = latE6s.length;
        if (len != lonE6s.length || len != ts.length) revert LengthMismatch();

        Proof storage p = _proofs[orderId];
        if (!p.exists) {
            p.exists = true;
            p.finalized = false;
            emit ProofInitialized(orderId, msg.sender);
        } else {
            if (p.finalized) revert AlreadyFinalized();
        }

        for (uint256 i = 0; i < len; ++i) {
            int256 lat = latE6s[i];
            int256 lon = lonE6s[i];
            uint256 t = ts[i];

            if (lat < type(int32).min || lat > type(int32).max) revert InvalidInput("lat OOB");
            if (lon < type(int32).min || lon > type(int32).max) revert InvalidInput("lon OOB");
            if (t > uint256(type(uint40).max)) revert InvalidInput("ts OOB");

            p.checkpoints.push(Checkpoint(int32(lat), int32(lon), uint40(t)));
            emit CheckpointAdded(orderId, int32(lat), int32(lon), uint40(t), msg.sender);
        }
    }

    /// @notice Append a single checkpoint
    function addCheckpoint(uint256 orderId, int256 latE6, int256 lonE6, uint256 ts) external {
        if (!_isUpdater(msg.sender)) revert NotAuthorized();
        if (orderId == 0 || ts == 0) revert InvalidInput("bad input");
        if (latE6 < type(int32).min || latE6 > type(int32).max) revert InvalidInput("lat OOB");
        if (lonE6 < type(int32).min || lonE6 > type(int32).max) revert InvalidInput("lon OOB");
        if (ts > uint256(type(uint40).max)) revert InvalidInput("ts OOB");

        Proof storage p = _proofs[orderId];
        if (!p.exists) {
            p.exists = true;
            p.finalized = false;
            emit ProofInitialized(orderId, msg.sender);
        } else {
            if (p.finalized) revert AlreadyFinalized();
        }

        p.checkpoints.push(Checkpoint(int32(latE6), int32(lonE6), uint40(ts)));
        emit CheckpointAdded(orderId, int32(latE6), int32(lonE6), uint40(ts), msg.sender);
    }

    /* --------------------------- EIP-712 Finalize --------------------------- */

    /// @notice Finalize using carrier signature (EIP-712) — relayed by backend
    function finalizeWithSig(
        uint256 orderId,
        address payee,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (orderId == 0 || payee == address(0)) revert InvalidInput("params");
        if (block.timestamp > deadline) revert SignatureExpired();

        Proof storage p = _proofs[orderId];
        if (!p.exists) revert ProofNotInit();
        if (p.finalized) revert AlreadyFinalized();

        uint256 nonce = nonces[orderId]++;
        bytes32 structHash = keccak256(abi.encode(FINALIZE_TYPEHASH, orderId, payee, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) revert BadSigner();

        // signer must be assigned carrier OR Admin
        address assigned = delivery.getAssignedCarrier(orderId);
        if (!(signer == assigned || registry.hasRole(signer, IAccessRegistry.Role.Admin))) revert BadSigner();

        // finalize: mark and notify DeliveryManagement and Escrow
        p.finalized = true;
        delivery.markDeliveredFromPoD(orderId);
        escrow.releasePayment(orderId);

        emit Finalized(orderId, block.timestamp, msg.sender, signer);
    }

    /* --------------------------- Views / Helpers --------------------------- */

    function proofExists(uint256 orderId) external view returns (bool) {
        return _proofs[orderId].exists;
    }

    function getProofSummary(uint256 orderId) external view returns (
        bool exists,
        bool finalized,
        uint256 checkpointCount
    ) {
        Proof storage p = _proofs[orderId];
        exists = p.exists;
        finalized = p.finalized;
        checkpointCount = p.checkpoints.length;
    }

    function getCheckpointCount(uint256 orderId) external view returns (uint256) {
        Proof storage p = _proofs[orderId];
        if (!p.exists) revert ProofNotInit();
        return p.checkpoints.length;
    }

    function getCheckpoints(uint256 orderId) external view returns (Checkpoint[] memory) {
        Proof storage p = _proofs[orderId];
        if (!p.exists) revert ProofNotInit();
        return p.checkpoints;
    }

    function isFinalized(uint256 orderId) external view returns (bool) {
        Proof storage p = _proofs[orderId];
        if (!p.exists) revert ProofNotInit();
        return p.finalized;
    }
}
