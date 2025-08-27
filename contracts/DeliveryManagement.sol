// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AccessRegistry.sol";

/// @title Delivery Management (Minimal)
/// @notice Create deliveries; only PoD can mark as Delivered
contract DeliveryManagement {
    error NotAuthorized();
    error InvalidInput();
    error DeliveryNotFound();

    enum Status { Created, InTransit, Delivered, Cancelled }

    struct Delivery {
        uint256 orderId;
        uint256 truckId;
        string origin;
        string destination;
        uint256 eta;          // unix
        Status status;
        address createdBy;
    }

    IAccessRegistry public immutable registry; // central RBAC
    address public owner;                      // simple owner
    address public proofOfDelivery;            // the only contract that can set Delivered

    uint256 private _nextOrderId = 1;
    mapping(uint256 => Delivery) private _deliveries;

    event DeliveryCreated(
        uint256 indexed orderId,
        uint256 truckId,
        string origin,
        string destination,
        uint256 eta,
        address indexed createdBy
    );
    event StatusUpdated(uint256 indexed orderId, Status newStatus, address indexed by);
    event ProofOfDeliverySet(address indexed pod, address indexed by);
    event OwnerTransferred(address indexed oldOwner, address indexed newOwner);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotAuthorized();
        _;
    }

    constructor(address accessRegistry) {
        require(accessRegistry != address(0), "zero registry");
        registry = IAccessRegistry(accessRegistry);
        owner = msg.sender;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero addr");
        emit OwnerTransferred(owner, newOwner);
        owner = newOwner;
    }

    /// @notice Owner sets PoD contract once deployed
    function setProofOfDelivery(address pod) external onlyOwner {
        require(pod != address(0), "zero pod");
        proofOfDelivery = pod;
        emit ProofOfDeliverySet(pod, msg.sender);
    }

    /// @notice Only FleetOwner or Carrier can create a delivery (simple rule)
    function createDelivery(
        uint256 truckId,
        string calldata origin,
        string calldata destination,
        uint256 eta
    ) external returns (uint256 orderId) {
        if (
            !registry.hasRole(msg.sender, IAccessRegistry.Role.FleetOwner) &&
            !registry.hasRole(msg.sender, IAccessRegistry.Role.Carrier)
        ) revert NotAuthorized();

        if (truckId == 0 || bytes(origin).length == 0 || bytes(destination).length == 0) {
            revert InvalidInput();
        }
        if (eta <= block.timestamp) revert InvalidInput();

        orderId = _nextOrderId++;
        _deliveries[orderId] = Delivery({
            orderId: orderId,
            truckId: truckId,
            origin: origin,
            destination: destination,
            eta: eta,
            status: Status.Created,
            createdBy: msg.sender
        });

        emit DeliveryCreated(orderId, truckId, origin, destination, eta, msg.sender);
    }

    /// @notice Creator or Owner can move to InTransit/Cancelled (but NOT Delivered)
    function setStatus(uint256 orderId, Status newStatus) external {
        Delivery storage d = _deliveries[orderId];
        if (d.orderId == 0) revert DeliveryNotFound();

        bool creatorOrOwner = (msg.sender == d.createdBy || msg.sender == owner);
        if (!creatorOrOwner) revert NotAuthorized();

        // Delivered is reserved for PoD finalize; block it here
        require(newStatus != Status.Delivered, "Delivered by PoD only");

        d.status = newStatus;
        emit StatusUpdated(orderId, newStatus, msg.sender);
    }

    /// @notice Called ONLY by the ProofOfDelivery contract to mark Delivered
    function markDeliveredFromPoD(uint256 orderId) external {
        if (msg.sender != proofOfDelivery) revert NotAuthorized();

        Delivery storage d = _deliveries[orderId];
        if (d.orderId == 0) revert DeliveryNotFound();

        d.status = Status.Delivered;
        emit StatusUpdated(orderId, Status.Delivered, msg.sender);
    }

    /// Views
    function getDelivery(uint256 orderId) external view returns (Delivery memory) {
        Delivery memory d = _deliveries[orderId];
        if (d.orderId == 0) revert DeliveryNotFound();
        return d;
    }

    function nextOrderId() external view returns (uint256) {
        return _nextOrderId;
    }
}
