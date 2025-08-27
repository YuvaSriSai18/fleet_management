// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Minimal interface for DeliveryManagement used to authorize releases
interface IDeliveryManagement {
    // Optional: you may validate delivery status if you add a view in DeliveryManagement
    // function getDeliveryStatus(uint256 orderId) external view returns (uint8);
}

/// @title PaymentEscrow (Minimal: ETH + ERC20)
/// @notice Hold funds for an order until DeliveryManagement releases them
contract PaymentEscrow {
    /* -------------------- Errors -------------------- */
    error NotOwner();
    error NotDeliveryContract();
    error EscrowExists();
    error EscrowNotFound();
    error EscrowAlreadyReleased();
    error InsufficientValue();
    error TransferFailed();
    error InvalidAmount();
    error InvalidAddress();

    /* -------------------- Types -------------------- */
    enum TokenType { ETH, ERC20 }

    struct EscrowEntry {
        address payer;
        address payee;
        TokenType tokenType;
        address token;    // erc20 address if tokenType==ERC20, else zero
        uint256 amount;   // amount in wei or token smallest units
        bool released;
    }

    /* -------------------- State -------------------- */
    address public owner;
    address public deliveryContract; // allowed to call releasePayment
    mapping(uint256 => EscrowEntry) public escrows; // orderId => escrow

    /* -------------------- Events -------------------- */
    event OwnerTransferred(address indexed oldOwner, address indexed newOwner);
    event DeliveryContractSet(address indexed deliveryContract, address indexed by);
    event EscrowCreatedETH(uint256 indexed orderId, address indexed payer, address indexed payee, uint256 amount);
    event EscrowCreatedERC20(uint256 indexed orderId, address indexed payer, address indexed payee, address token, uint256 amount);
    event PaymentReleased(uint256 indexed orderId, address indexed to, uint256 amount);
    event EscrowRefunded(uint256 indexed orderId, address indexed to, uint256 amount);
    event PenaltyApplied(uint256 indexed orderId, uint256 penaltyAmount, address indexed to);

    /* -------------------- Modifiers -------------------- */
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyDelivery() {
        if (msg.sender != deliveryContract) revert NotDeliveryContract();
        _;
    }

    constructor(address _deliveryContract) {
        owner = msg.sender;
        if (_deliveryContract != address(0)) {
            deliveryContract = _deliveryContract;
            emit DeliveryContractSet(_deliveryContract, msg.sender);
        }
    }

    /* -------------------- Admin -------------------- */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        emit OwnerTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setDeliveryContract(address _deliveryContract) external onlyOwner {
        if (_deliveryContract == address(0)) revert InvalidAddress();
        deliveryContract = _deliveryContract;
        emit DeliveryContractSet(_deliveryContract, msg.sender);
    }

    /* -------------------- Escrow Creation -------------------- */

    /// @notice Create an ETH escrow for `orderId`. Must send exactly `amount` as msg.value.
    /// @dev Reverts if escrow already exists for orderId.
    function createEscrowETH(uint256 orderId, address payee) external payable {
        if (orderId == 0) revert InvalidAmount();
        if (payee == address(0)) revert InvalidAddress();
        if (msg.value == 0) revert InvalidAmount();
        EscrowEntry storage e = escrows[orderId];
        if (e.payer != address(0)) revert EscrowExists();

        escrows[orderId] = EscrowEntry({
            payer: msg.sender,
            payee: payee,
            tokenType: TokenType.ETH,
            token: address(0),
            amount: msg.value,
            released: false
        });

        emit EscrowCreatedETH(orderId, msg.sender, payee, msg.value);
    }

    /// @notice Create an ERC20 escrow for `orderId`. Caller must `approve` this contract first.
    /// @dev Transfers tokens from payer into escrow.
    function createEscrowERC20(uint256 orderId, address payee, address token, uint256 amount) external {
        if (orderId == 0) revert InvalidAmount();
        if (payee == address(0) || token == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        EscrowEntry storage e = escrows[orderId];
        if (e.payer != address(0)) revert EscrowExists();

        // pull tokens in
        bool ok = IERC20(token).transferFrom(msg.sender, address(this), amount);
        if (!ok) revert TransferFailed();

        escrows[orderId] = EscrowEntry({
            payer: msg.sender,
            payee: payee,
            tokenType: TokenType.ERC20,
            token: token,
            amount: amount,
            released: false
        });

        emit EscrowCreatedERC20(orderId, msg.sender, payee, token, amount);
    }

    /* -------------------- Release / Refund -------------------- */

    /// @notice Release payment to payee for the given `orderId`.
    /// @dev Only callable by the linked DeliveryManagement contract (i.e., after delivery finalized).
    function releasePayment(uint256 orderId) external onlyDelivery {
        EscrowEntry storage e = escrows[orderId];
        if (e.payer == address(0)) revert EscrowNotFound();
        if (e.released) revert EscrowAlreadyReleased();

        e.released = true;
        uint256 amount = e.amount;
        address payee = e.payee;
        if (e.tokenType == TokenType.ETH) {
            // send ETH
            (bool sent, ) = payee.call{ value: amount }("");
            if (!sent) revert TransferFailed();
        } else {
            // send ERC20
            bool ok = IERC20(e.token).transfer(payee, amount);
            if (!ok) revert TransferFailed();
        }

        emit PaymentReleased(orderId, payee, amount);
    }

    /// @notice Refund escrow to payer (callable by payer). Only allowed if not released.
    function refund(uint256 orderId) external {
        EscrowEntry storage e = escrows[orderId];
        if (e.payer == address(0)) revert EscrowNotFound();
        if (e.released) revert EscrowAlreadyReleased();
        if (msg.sender != e.payer) revert NotOwner();

        e.released = true; // mark to prevent re-entrancy / double refunds
        uint256 amount = e.amount;

        if (e.tokenType == TokenType.ETH) {
            (bool sent, ) = e.payer.call{ value: amount }("");
            if (!sent) revert TransferFailed();
        } else {
            bool ok = IERC20(e.token).transfer(e.payer, amount);
            if (!ok) revert TransferFailed();
        }
        emit EscrowRefunded(orderId, e.payer, amount);
    }

    /* -------------------- Penalty (optional small helper) -------------------- */

    /// @notice Apply a penalty amount (deducted from escrow) and send penalty to `to`.
    /// @dev Callable by owner (admin) or deliveryContract. Keeps remaining funds in escrow for normal release/refund.
    function applyPenalty(uint256 orderId, uint256 penaltyAmount, address to) external {
        EscrowEntry storage e = escrows[orderId];
        if (e.payer == address(0)) revert EscrowNotFound();
        if (e.released) revert EscrowAlreadyReleased();
        if (penaltyAmount == 0 || penaltyAmount > e.amount) revert InvalidAmount();
        if (to == address(0)) revert InvalidAddress();

        // allow owner or deliveryContract to apply penalty
        if (msg.sender != owner && msg.sender != deliveryContract) revert NotOwner();

        // deduct
        e.amount -= penaltyAmount;

        if (e.tokenType == TokenType.ETH) {
            (bool sent, ) = to.call{ value: penaltyAmount }("");
            if (!sent) revert TransferFailed();
        } else {
            bool ok = IERC20(e.token).transfer(to, penaltyAmount);
            if (!ok) revert TransferFailed();
        }

        emit PenaltyApplied(orderId, penaltyAmount, to);
    }

    /* -------------------- Views / helpers -------------------- */

    function getEscrow(uint256 orderId) external view returns (
        address payer,
        address payee,
        TokenType tokenType,
        address token,
        uint256 amount,
        bool released
    ) {
        EscrowEntry storage e = escrows[orderId];
        if (e.payer == address(0)) revert EscrowNotFound();
        return (e.payer, e.payee, e.tokenType, e.token, e.amount, e.released);
    }

    /* -------------------- Fallbacks -------------------- */
    // allow contract to receive ETH (used for createEscrowETH only)
    receive() external payable {}
    fallback() external payable {}
}
