// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./DeliveryManagement.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title Proof of Delivery (PoD)
/// @notice Tamper-proof GPS checkpoint log + finalization hook to DeliveryManagement
contract ProofOfDelivery is AccessControl {
    DeliveryManagement private deliveryContract;

    /// @dev Role for accounts (drivers, backends, fleet managers) that can add checkpoints/finalize
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    constructor(address _deliveryContract) {
        require(_deliveryContract != address(0), "Invalid DeliveryManagement address");
        deliveryContract = DeliveryManagement(_deliveryContract);

        // Grant deployer full admin rights
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// -----------------------------------------------------------------------
    /// 📍 Data structures
    /// -----------------------------------------------------------------------
    struct Checkpoint {
        uint256 lat;        // latitude * 1e6
        uint256 longi;      // longitude * 1e6
        uint256 timestamp;  // Unix time when recorded
    }

    struct DeliveryProof {
        uint256 orderId;
        bool finalized;
        Checkpoint[] checkpoints;
    }

    mapping(uint256 => DeliveryProof) private proofs;

    /// -----------------------------------------------------------------------
    /// 📣 Events
    /// -----------------------------------------------------------------------
    event CheckpointAdded(uint256 indexed orderId, uint256 lat, uint256 longi, uint256 timestamp);
    event DeliveryFinalized(uint256 indexed orderId, uint256 timestamp, address finalizedBy);

    /// -----------------------------------------------------------------------
    /// 🔐 Admin functions
    /// -----------------------------------------------------------------------
    function authorizeUpdater(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(UPDATER_ROLE, account);
    }

    function deauthorizeUpdater(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(UPDATER_ROLE, account);
    }

    /// -----------------------------------------------------------------------
    /// 🚚 Proof-of-Delivery functions
    /// -----------------------------------------------------------------------

    /// @notice Add a GPS checkpoint; auto-initializes proof on first use
    function addCheckpoint(
        uint256 orderId,
        uint256 lat,
        uint256 longi,
        uint256 timestamp
    ) external {
        require(
            hasRole(UPDATER_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Not authorized"
        );
        require(orderId != 0, "Invalid orderId");
        require(timestamp != 0, "Invalid timestamp");

        DeliveryProof storage proof = proofs[orderId];

        // Auto-initialize on first checkpoint
        if (proof.orderId == 0) {
            proof.orderId = orderId;
            proof.finalized = false;
        } else {
            require(!proof.finalized, "Delivery already finalized");
        }

        proof.checkpoints.push(Checkpoint(lat, longi, timestamp));
        emit CheckpointAdded(orderId, lat, longi, timestamp);
    }

    /// @notice Finalize PoD and update DeliveryManagement to Delivered
    function finalizeDelivery(uint256 orderId) external {
        require(
            hasRole(UPDATER_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Not authorized"
        );

        DeliveryProof storage proof = proofs[orderId];
        require(proof.orderId != 0, "Delivery proof not initialized");
        require(!proof.finalized, "Already finalized");

        proof.finalized = true;

        // 🔗 Update DeliveryManagement status
        deliveryContract.updateDeliveryStatus(
            orderId,
            DeliveryManagement.DeliveryStatus.Delivered
        );

        emit DeliveryFinalized(orderId, block.timestamp, msg.sender);
    }

    /// -----------------------------------------------------------------------
    /// 🔎 View helpers
    /// -----------------------------------------------------------------------
    function proofExists(uint256 orderId) external view returns (bool) {
        return proofs[orderId].orderId != 0;
    }

    function isFinalized(uint256 orderId) external view returns (bool) {
        DeliveryProof storage proof = proofs[orderId];
        if (proof.orderId == 0) return false;
        return proof.finalized;
    }

    function getCheckpoints(uint256 orderId) external view returns (Checkpoint[] memory) {
        require(proofs[orderId].orderId != 0, "Delivery proof not initialized");
        return proofs[orderId].checkpoints;
    }

    function getDeliveryManagement() external view returns (address) {
        return address(deliveryContract);
    }
}
