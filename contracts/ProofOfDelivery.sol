// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IAccessRegistry {
    enum Role {
        None,
        Admin,
        FleetOwner,
        Carrier,
        ThirdPartyLogistics,
        Customer
    }

    function hasRole(address account, Role role) external view returns (bool);
}

interface IDeliveryManagement {
    function markDeliveredFromPoD(uint256 orderId) external;

    function getAssignedCarrier(
        uint256 orderId
    ) external view returns (address);
}

interface IPaymentEscrow {
    function releasePayment(uint256 orderId) external;
}

/// @title ProofOfDelivery with Checkpoints
/// @notice Supports bulk/single checkpoint addition + marking checkpoints reached
contract ProofOfDeliverySig {
    /* --------------------------- Errors --------------------------- */
    error NotAuthorized();
    error InvalidInput(string);
    error ProofNotInit();
    error AlreadyFinalized();
    error LengthMismatch();
    error CheckpointAlreadyReached();

    /* --------------------------- Types --------------------------- */
    struct Checkpoint {
        int32 latE6;
        int32 lonE6;
        uint40 plannedTime; // optional planned timestamp
        uint40 actualTime; // 0 if not yet reached
    }

    struct Proof {
        bool exists;
        bool finalized;
        Checkpoint[] checkpoints;
    }

    /* --------------------------- State --------------------------- */
    IAccessRegistry public immutable registry;
    IDeliveryManagement public immutable delivery;
    IPaymentEscrow public immutable escrow;
    address public owner;

    mapping(uint256 => Proof) private _proofs;

    /* --------------------------- Events --------------------------- */
    event ProofInitialized(uint256 indexed orderId, address indexed by);
    event CheckpointAdded(
        uint256 indexed orderId,
        uint256 index,
        int32 latE6,
        int32 lonE6,
        uint40 plannedTime,
        address indexed by
    );
    event CheckpointReached(
        uint256 indexed orderId,
        uint256 index,
        uint40 actualTime,
        address indexed by
    );
    event Finalized(uint256 indexed orderId, uint256 time, address indexed by);
    event OwnerTransferred(address indexed oldOwner, address indexed newOwner);

    /* --------------------------- Modifiers --------------------------- */
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotAuthorized();
        _;
    }

    constructor(
        address accessRegistry,
        address deliveryContract,
        address escrowContract
    ) {
        require(
            accessRegistry != address(0) &&
                deliveryContract != address(0) &&
                escrowContract != address(0),
            "zero addr"
        );
        registry = IAccessRegistry(accessRegistry);
        delivery = IDeliveryManagement(deliveryContract);
        escrow = IPaymentEscrow(escrowContract);
        owner = msg.sender;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero addr");
        emit OwnerTransferred(owner, newOwner);
        owner = newOwner;
    }

    function _isUpdater(address a) internal view returns (bool) {
        return
            registry.hasRole(a, IAccessRegistry.Role.Admin) ||
            registry.hasRole(a, IAccessRegistry.Role.FleetOwner) ||
            registry.hasRole(a, IAccessRegistry.Role.Carrier) ||
            a == owner;
    }

    /* --------------------------- Proof Lifecycle --------------------------- */

    /// Initialize proof
    function initProof(uint256 orderId) external {
        if (orderId == 0) revert InvalidInput("orderId==0");
        Proof storage p = _proofs[orderId];
        if (p.exists) revert InvalidInput("exists");
        p.exists = true;
        p.finalized = false;
        emit ProofInitialized(orderId, msg.sender);
    }

    /// Bulk add checkpoints
    function createProofWithCheckpoints(
        uint256 orderId,
        int256[] calldata latE6s,
        int256[] calldata lonE6s,
        uint256[] calldata plannedTimes
    ) external {
        if (!_isUpdater(msg.sender)) revert NotAuthorized();
        if (orderId == 0) revert InvalidInput("orderId==0");

        uint256 len = latE6s.length;
        if (len != lonE6s.length || len != plannedTimes.length)
            revert LengthMismatch();

        Proof storage p = _proofs[orderId];
        if (!p.exists) {
            p.exists = true;
            p.finalized = false;
            emit ProofInitialized(orderId, msg.sender);
        } else if (p.finalized) {
            revert AlreadyFinalized();
        }

        for (uint256 i = 0; i < len; ++i) {
            int256 lat = latE6s[i];
            int256 lon = lonE6s[i];
            uint256 ts = plannedTimes[i];

            if (lat < type(int32).min || lat > type(int32).max)
                revert InvalidInput("lat OOB");
            if (lon < type(int32).min || lon > type(int32).max)
                revert InvalidInput("lon OOB");
            if (ts > type(uint40).max) revert InvalidInput("ts OOB");

            uint256 idx = p.checkpoints.length;
            p.checkpoints.push(
                Checkpoint(int32(lat), int32(lon), uint40(ts), 0)
            );
            emit CheckpointAdded(
                orderId,
                idx,
                int32(lat),
                int32(lon),
                uint40(ts),
                msg.sender
            );
        }
    }

    /// Single checkpoint addition
    function addCheckpoint(
        uint256 orderId,
        int256 latE6,
        int256 lonE6,
        uint256 plannedTime
    ) external {
        if (!_isUpdater(msg.sender)) revert NotAuthorized();
        if (orderId == 0) revert InvalidInput("bad input");
        if (latE6 < type(int32).min || latE6 > type(int32).max)
            revert InvalidInput("lat OOB");
        if (lonE6 < type(int32).min || lonE6 > type(int32).max)
            revert InvalidInput("lon OOB");
        if (plannedTime > uint256(type(uint40).max))
            revert InvalidInput("ts OOB");

        Proof storage p = _proofs[orderId];
        if (!p.exists) {
            p.exists = true;
            p.finalized = false;
            emit ProofInitialized(orderId, msg.sender);
        } else if (p.finalized) {
            revert AlreadyFinalized();
        }

        uint256 idx = p.checkpoints.length;
        p.checkpoints.push(
            Checkpoint(int32(latE6), int32(lonE6), uint40(plannedTime), 0)
        );
        emit CheckpointAdded(
            orderId,
            idx,
            int32(latE6),
            int32(lonE6),
            uint40(plannedTime),
            msg.sender
        );
    }

    /// Mark checkpoint reached
    function markCheckpointReached(
        uint256 orderId,
        uint256 index,
        uint256 actualTime
    ) external {
        if (!_isUpdater(msg.sender)) revert NotAuthorized();
        Proof storage p = _proofs[orderId];
        if (!p.exists) revert ProofNotInit();
        if (p.finalized) revert AlreadyFinalized();
        if (index >= p.checkpoints.length) revert InvalidInput("bad index");
        if (actualTime > type(uint40).max) revert InvalidInput("ts OOB");

        Checkpoint storage cp = p.checkpoints[index];
        if (cp.actualTime != 0) revert CheckpointAlreadyReached();

        cp.actualTime = uint40(actualTime);
        emit CheckpointReached(orderId, index, uint40(actualTime), msg.sender);
    }

    /* --------------------------- Finalization --------------------------- */
    function finalizeDelivery(uint256 orderId, address payee) external {
        if (orderId == 0 || payee == address(0)) revert InvalidInput("params");

        Proof storage p = _proofs[orderId];
        if (!p.exists) revert ProofNotInit();
        if (p.finalized) revert AlreadyFinalized();

        // Only assigned carrier or Admin can finalize
        address assigned = delivery.getAssignedCarrier(orderId);
        if (
            !(msg.sender == assigned ||
                registry.hasRole(msg.sender, IAccessRegistry.Role.Admin))
        ) {
            revert NotAuthorized();
        }

        p.finalized = true;
        delivery.markDeliveredFromPoD(orderId);
        escrow.releasePayment(orderId);

        emit Finalized(orderId, block.timestamp, msg.sender);
    }

    /* --------------------------- Views --------------------------- */
    function proofExists(uint256 orderId) external view returns (bool) {
        return _proofs[orderId].exists;
    }

    function getProofSummary(
        uint256 orderId
    )
        external
        view
        returns (bool exists, bool finalized, uint256 checkpointCount)
    {
        Proof storage p = _proofs[orderId];
        exists = p.exists;
        finalized = p.finalized;
        checkpointCount = p.checkpoints.length;
    }

    function getCheckpointCount(
        uint256 orderId
    ) external view returns (uint256) {
        Proof storage p = _proofs[orderId];
        if (!p.exists) revert ProofNotInit();
        return p.checkpoints.length;
    }

    function getCheckpoints(
        uint256 orderId
    ) external view returns (Checkpoint[] memory) {
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
