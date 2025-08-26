// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Delivery Management Contract
/// @notice Immutable record-keeping of shipments, trucks, and routes
contract DeliveryManagement {
    /// @notice Delivery status options
    enum DeliveryStatus {
        Created,
        InTransit,
        Delivered,
        Cancelled
    }

    /// @notice Struct to store delivery details
    struct Delivery {
        uint256 orderId;
        uint256 truckId;
        string origin;
        string destination;
        uint256 eta; // Estimated arrival timestamp (Unix)
        DeliveryStatus status;
        address createdBy; // who created this delivery
    }

    /// @notice Mapping orderId -> Delivery
    mapping(uint256 => Delivery) private deliveries;

    /// @notice Counter for auto-incrementing order IDs
    uint256 private nextOrderId = 1;

    /// @notice Admin for management actions (set at deployment)
    address public admin;

    /// @notice Registered ProofOfDelivery contract that is allowed to finalize deliveries
    address public proofOfDelivery;

    /// @notice Events for transparency
    event DeliveryCreated(
        uint256 indexed orderId,
        uint256 truckId,
        string origin,
        string destination,
        uint256 eta,
        DeliveryStatus status,
        address indexed createdBy
    );

    event DeliveryStatusUpdated(
        uint256 indexed orderId,
        DeliveryStatus newStatus,
        uint256 timestamp,
        address indexed updatedBy
    );

    event ProofOfDeliverySet(address indexed podAddress, address indexed setBy);

    /// @notice Modifier to restrict to admin
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    /// @notice Construct with admin = deployer
    constructor() {
        admin = msg.sender;
    }

    /// @notice Create a new delivery record (orderId auto-generated)
    /// @param truckId Truck assigned to the delivery
    /// @param origin Pickup location
    /// @param destination Drop-off location
    /// @param eta Estimated time of arrival (Unix timestamp)
    /// @return orderId The system-generated unique delivery ID
    function createDelivery(
        uint256 truckId,
        string memory origin,
        string memory destination,
        uint256 eta
    ) external returns (uint256 orderId) {
        require(truckId > 0, "Invalid truckId");
        require(bytes(origin).length > 0, "Origin required");
        require(bytes(destination).length > 0, "Destination required");
        require(eta > block.timestamp, "ETA must be in future");

        orderId = nextOrderId; // assign current counter
        nextOrderId++; // increment for next use

        deliveries[orderId] = Delivery({
            orderId: orderId,
            truckId: truckId,
            origin: origin,
            destination: destination,
            eta: eta,
            status: DeliveryStatus.Created,
            createdBy: msg.sender
        });

        emit DeliveryCreated(
            orderId,
            truckId,
            origin,
            destination,
            eta,
            DeliveryStatus.Created,
            msg.sender
        );
    }

    /// @notice Set the ProofOfDelivery contract address (only admin)
    /// @param _pod address of the deployed ProofOfDelivery contract
    function setProofOfDelivery(address _pod) external onlyAdmin {
        require(_pod != address(0), "Invalid PoD address");
        proofOfDelivery = _pod;
        emit ProofOfDeliverySet(_pod, msg.sender);
    }

    /// @notice Update the status of a delivery
    /// @dev Allows the original creator, the admin, or the registered PoD contract
    function updateDeliveryStatus(uint256 orderId, DeliveryStatus newStatus) external {
        Delivery storage d = deliveries[orderId];
        require(d.orderId != 0, "Delivery not found");

        // Allow update if msg.sender is the creator, admin, or registered PoD contract
        require(
            msg.sender == d.createdBy || msg.sender == admin || msg.sender == proofOfDelivery,
            "Not authorized to update"
        );

        d.status = newStatus;

        emit DeliveryStatusUpdated(orderId, newStatus, block.timestamp, msg.sender);
    }

    /// @notice Get details of a delivery
    function getDelivery(uint256 orderId)
        external
        view
        returns (
            uint256,
            uint256,
            string memory,
            string memory,
            uint256,
            DeliveryStatus,
            address
        )
    {
        Delivery memory d = deliveries[orderId];
        require(d.orderId != 0, "Delivery not found");
        return (
            d.orderId,
            d.truckId,
            d.origin,
            d.destination,
            d.eta,
            d.status,
            d.createdBy
        );
    }

    /// @notice Get the latest orderId that will be assigned
    function getNextOrderId() external view returns (uint256) {
        return nextOrderId;
    }

    /// @notice Optional: allow admin to transfer admin to a new address
    function transferAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Invalid admin");
        admin = newAdmin;
    }
}
