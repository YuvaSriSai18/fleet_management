// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Access Registry (Minimal RBAC)
/// @notice Centralized role registry for all contracts
interface IAccessRegistry {
    enum Role { None, Admin, FleetOwner, Carrier, ThirdPartyLogistics, Customer }
    function hasRole(address account, Role role) external view returns (bool);
}

contract AccessRegistry is IAccessRegistry {
    error NotOwner();
    error InvalidRole();

    address public owner;

    // account => role => bool
    mapping(address => mapping(Role => bool)) private _roles;

    event OwnerTransferred(address indexed oldOwner, address indexed newOwner);
    event RoleGranted(address indexed account, Role indexed role, address indexed by);
    event RoleRevoked(address indexed account, Role indexed role, address indexed by);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
        _roles[msg.sender][Role.Admin] = true;
        emit RoleGranted(msg.sender, Role.Admin, msg.sender);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero addr");
        emit OwnerTransferred(owner, newOwner);
        owner = newOwner;
    }

    function grantRole(address account, Role role) external onlyOwner {
        if (role == Role.None) revert InvalidRole();
        _roles[account][role] = true;
        emit RoleGranted(account, role, msg.sender);
    }

    function revokeRole(address account, Role role) external onlyOwner {
        if (role == Role.None) revert InvalidRole();
        _roles[account][role] = false;
        emit RoleRevoked(account, role, msg.sender);
    }

    function hasRole(address account, Role role) public view override returns (bool) {
        return _roles[account][role];
    }
}
