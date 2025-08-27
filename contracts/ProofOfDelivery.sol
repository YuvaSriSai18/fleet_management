// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal interface for the Access Registry used by this contract.
/// Ensure your AccessRegistry implements the same enum & hasRole signature.
interface IAccessRegistry {
    enum Role { None, Admin, FleetOwner, Carrier, ThirdPartyLogistics, Customer }
    function hasRole(address account, Role role) external view returns (bool);
}

/// @notice Minimal interface to interact with your DeliveryManagement contract.
/// This contract calls `markDeliveredFromPoD(orderId)` to mark deliveries delivered.
interface IDeliveryManagement {
    function markDeliveredFromPoD(uint256 orderId) external;
}

/// @title ProofOfDelivery (robust, small)
/// @notice Add checkpoints (optional) and finalize deliveries; uses AccessRegistry for role checks.
contract ProofOfDelivery {
    /* ---------------------------
       Errors
       --------------------------- */
    error NotAuthorized();
    error InvalidInput(string reason);
    error ProofNotInit();
    error AlreadyFinalized();
    error OutOfRange(string field);

    /* ---------------------------
       Types
       --------------------------- */
    struct Checkpoint {
        int32 latE6;     // latitude * 1e6
        int32 lonE6;     // longitude * 1e6
        uint40 time;     // seconds since epoch
    }

    struct Proof {
        bool exists;
        bool finalized;
        Checkpoint[] checkpoints;
    }

    /* ---------------------------
       State
       --------------------------- */
    IAccessRegistry public immutable registry;
    IDeliveryManagement public immutable delivery;
    address public owner;

    mapping(uint256 => Proof) private _proofs;

    /* ---------------------------
       Events
       --------------------------- */
    event ProofInitialized(uint256 indexed orderId, address indexed by);
    event CheckpointAdded(uint256 indexed orderId, int32 latE6, int32 lonE6, uint40 time, address indexed by);
    event Finalized(uint256 indexed orderId, uint256 time, address indexed by);
    event OwnerTransferred(address indexed oldOwner, address indexed newOwner);

    /* ---------------------------
       Modifiers
       --------------------------- */
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotAuthorized();
        _;
    }

    constructor(address accessRegistry, address deliveryContract) {
        require(accessRegistry != address(0) && deliveryContract != address(0), "zero address");
        registry = IAccessRegistry(accessRegistry);
        delivery = IDeliveryManagement(deliveryContract);
        owner = msg.sender;
    }

    /* ---------------------------
       Admin
       --------------------------- */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero addr");
        emit OwnerTransferred(owner, newOwner);
        owner = newOwner;
    }

    /* ---------------------------
       Helpers
       --------------------------- */
    /// @notice who can act as an updater (write checkpoints / finalize)
    function _isUpdater(address a) internal view returns (bool) {
        return registry.hasRole(a, IAccessRegistry.Role.FleetOwner)
            || registry.hasRole(a, IAccessRegistry.Role.Carrier)
            || registry.hasRole(a, IAccessRegistry.Role.Admin); // allow Admins too
    }

    /* ---------------------------
       Proof lifecycle
       --------------------------- */

    /// @notice Explicitly initialize a proof for an order. Optional (addCheckpoint will auto-init).
    function initProof(uint256 orderId) external {
        if (orderId == 0) revert InvalidInput("orderId==0");
        Proof storage p = _proofs[orderId];
        if (p.exists) revert InvalidInput("proof already exists");
        p.exists = true;
        p.finalized = false;
        emit ProofInitialized(orderId, msg.sender);
    }

    /// @notice Append a checkpoint. If proof not initialized, auto-initialize it.
    /// @param orderId delivery order id (non-zero)
    /// @param latE6 latitude multiplied by 1e6 (can pass integer like 17385044 for 17.385044)
    /// @param lonE6 longitude multiplied by 1e6
    /// @param ts seconds since epoch (always pass seconds, not milliseconds)
    function addCheckpoint(
        uint256 orderId,
        int256 latE6,
        int256 lonE6,
        uint256 ts
    ) external {
        // Authorization
        if (!_isUpdater(msg.sender) && msg.sender != owner) revert NotAuthorized();

        // Basic inputs
        if (orderId == 0) revert InvalidInput("orderId==0");
        if (ts == 0) revert InvalidInput("timestamp==0");

        // Validate ranges before casting
        if (latE6 < type(int32).min || latE6 > type(int32).max) revert OutOfRange("latE6");
        if (lonE6 < type(int32).min || lonE6 > type(int32).max) revert OutOfRange("lonE6");
        if (ts > uint256(type(uint40).max)) revert OutOfRange("timestamp exceeds uint40");

        int32 lat32 = int32(latE6);
        int32 lon32 = int32(lonE6);
        uint40 ts40 = uint40(ts);

        Proof storage p = _proofs[orderId];

        // Auto-init if not exists
        if (!p.exists) {
            p.exists = true;
            p.finalized = false;
            emit ProofInitialized(orderId, msg.sender);
        } else {
            if (p.finalized) revert AlreadyFinalized();
        }

        p.checkpoints.push(Checkpoint({ latE6: lat32, lonE6: lon32, time: ts40 }));
        emit CheckpointAdded(orderId, lat32, lon32, ts40, msg.sender);
    }

    /// @notice Finalize proof and mark delivery as Delivered in DeliveryManagement.
    /// Can be called with zero checkpoints (allowed).
    function finalize(uint256 orderId) external {
        // Authorization
        if (!_isUpdater(msg.sender) && msg.sender != owner) revert NotAuthorized();

        Proof storage p = _proofs[orderId];
        if (!p.exists) revert ProofNotInit();
        if (p.finalized) revert AlreadyFinalized();

        p.finalized = true;

        // Call DeliveryManagement to mark delivered (must be implemented there)
        delivery.markDeliveredFromPoD(orderId);

        emit Finalized(orderId, block.timestamp, msg.sender);
    }

    /* ---------------------------
       Views
       --------------------------- */
    function proofExists(uint256 orderId) external view returns (bool) {
        return _proofs[orderId].exists;
    }

    function isFinalized(uint256 orderId) external view returns (bool) {
        Proof storage p = _proofs[orderId];
        return p.exists && p.finalized;
    }

    function getCheckpoints(uint256 orderId) external view returns (Checkpoint[] memory) {
        Proof storage p = _proofs[orderId];
        if (!p.exists) revert ProofNotInit();
        return p.checkpoints;
    }
}
