// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AccessRegistry.sol";

/// @title Delivery Management
/// @notice Handles order lifecycle (create, assign, transit, cancel, deliver)
contract DeliveryManagement {
    error NotAuthorized();
    error InvalidInput();
    error DeliveryNotFound();

    enum Status {
        Created,
        InTransit,
        Delivered,
        Cancelled
    }

    struct Delivery {
        uint256 orderId;
        string truckId; // changed to string
        string origin;
        string destination;
        uint256 eta; // unix timestamp
        Status status;
        address createdBy;
    }

    IAccessRegistry public immutable registry;
    address public owner;
    address public proofOfDelivery; // only this can mark Delivered

    uint256 private _nextOrderId = 1;
    mapping(uint256 => Delivery) private _deliveries;
    mapping(uint256 => address) private _assignedCarrier;

    event DeliveryCreated(
        uint256 indexed orderId,
        string truckId,
        string origin,
        string destination,
        uint256 eta,
        address indexed by
    );
    event CarrierAssigned(
        uint256 indexed orderId,
        address indexed carrier,
        address indexed by
    );
    event StatusUpdated(
        uint256 indexed orderId,
        Status newStatus,
        address indexed by
    );
    event ProofOfDeliverySet(address indexed pod, address indexed by);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotAuthorized();
        _;
    }

    constructor(address accessRegistry) {
        require(accessRegistry != address(0), "zero registry");
        registry = IAccessRegistry(accessRegistry);
        owner = msg.sender;
    }

    function setProofOfDelivery(address pod) external onlyOwner {
        require(pod != address(0), "zero pod");
        proofOfDelivery = pod;
        emit ProofOfDeliverySet(pod, msg.sender);
    }

    function createDelivery(
        string calldata truckId,
        string calldata origin,
        string calldata destination,
        uint256 eta
    ) external returns (uint256 orderId) {
        if (
            !registry.hasRole(msg.sender, IAccessRegistry.Role.FleetOwner) &&
            !registry.hasRole(msg.sender, IAccessRegistry.Role.Carrier)
        ) revert NotAuthorized();

        if (
            bytes(truckId).length == 0 ||
            bytes(origin).length == 0 ||
            bytes(destination).length == 0
        ) revert InvalidInput();
        if (eta <= block.timestamp) revert InvalidInput();

        orderId = _nextOrderId++;
        _deliveries[orderId] = Delivery(
            orderId,
            truckId,
            origin,
            destination,
            eta,
            Status.Created,
            msg.sender
        );
        emit DeliveryCreated(
            orderId,
            truckId,
            origin,
            destination,
            eta,
            msg.sender
        );
    }

    function assignCarrier(uint256 orderId, address carrier) external {
        Delivery storage d = _deliveries[orderId];
        if (d.orderId == 0) revert DeliveryNotFound();
        if (msg.sender != d.createdBy && msg.sender != owner)
            revert NotAuthorized();
        require(carrier != address(0), "zero carrier");
        _assignedCarrier[orderId] = carrier;
        emit CarrierAssigned(orderId, carrier, msg.sender);
    }

    function setStatus(uint256 orderId, Status newStatus) external {
        Delivery storage d = _deliveries[orderId];
        if (d.orderId == 0) revert DeliveryNotFound();
        if (
            msg.sender != d.createdBy &&
            msg.sender != owner &&
            msg.sender != _assignedCarrier[orderId]
        ) revert NotAuthorized();
        require(newStatus != Status.Delivered, "Delivered by PoD only");
        d.status = newStatus;
        emit StatusUpdated(orderId, newStatus, msg.sender);
    }

    function markDeliveredFromPoD(uint256 orderId) external {
        if (msg.sender != proofOfDelivery) revert NotAuthorized();
        Delivery storage d = _deliveries[orderId];
        if (d.orderId == 0) revert DeliveryNotFound();
        d.status = Status.Delivered;
        emit StatusUpdated(orderId, Status.Delivered, msg.sender);
    }

    function getDelivery(
        uint256 orderId
    ) external view returns (Delivery memory) {
        Delivery memory d = _deliveries[orderId];
        if (d.orderId == 0) revert DeliveryNotFound();
        return d;
    }

    function getAssignedCarrier(
        uint256 orderId
    ) external view returns (address) {
        if (_deliveries[orderId].orderId == 0) revert DeliveryNotFound();
        return _assignedCarrier[orderId];
    }

    function getStatus(uint256 orderId) external view returns (Status) {
        Delivery memory d = _deliveries[orderId];
        if (d.orderId == 0) revert DeliveryNotFound();
        return d.status;
    }

    function nextOrderId() external view returns (uint256) {
        return _nextOrderId;
    }
}
