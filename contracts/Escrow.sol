// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PaymentEscrow {
    error NotOwner();
    error NotPoD();
    error EscrowExists();
    error EscrowNotFound();
    error AlreadyReleased();
    error InvalidAddress();
    error InvalidAmount();
    error TransferFailed();

    enum TokenType {
        ETH,
        ERC20
    }

    struct EscrowEntry {
        address payer;
        address payee;
        TokenType tokenType;
        address token;
        uint256 amount;
        bool released;
    }

    address public owner;
    address public podContract;
    mapping(uint256 => EscrowEntry) public escrows;

    event EscrowCreated(
        uint256 indexed orderId,
        address indexed payer,
        address indexed payee,
        uint256 amount,
        TokenType tokenType
    );
    event PaymentReleased(uint256 indexed orderId, address to, uint256 amount);
    event Refunded(uint256 indexed orderId, address to, uint256 amount);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyPoD() {
        if (msg.sender != podContract) revert NotPoD();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setPoDContract(address pod) external onlyOwner {
        if (pod == address(0)) revert InvalidAddress();
        podContract = pod;
    }

    function createEscrowETH(uint256 orderId, address payee) external payable {
        if (orderId == 0 || payee == address(0)) revert InvalidAddress();
        if (msg.value == 0) revert InvalidAmount();
        if (escrows[orderId].payer != address(0)) revert EscrowExists();

        escrows[orderId] = EscrowEntry(
            msg.sender,
            payee,
            TokenType.ETH,
            address(0),
            msg.value,
            false
        );
        emit EscrowCreated(
            orderId,
            msg.sender,
            payee,
            msg.value,
            TokenType.ETH
        );
    }

    function createEscrowERC20(
        uint256 orderId,
        address payee,
        address token,
        uint256 amount
    ) external {
        if (orderId == 0 || payee == address(0) || token == address(0))
            revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (escrows[orderId].payer != address(0)) revert EscrowExists();

        if (!IERC20(token).transferFrom(msg.sender, address(this), amount))
            revert TransferFailed();

        escrows[orderId] = EscrowEntry(
            msg.sender,
            payee,
            TokenType.ERC20,
            token,
            amount,
            false
        );
        emit EscrowCreated(orderId, msg.sender, payee, amount, TokenType.ERC20);
    }

    function releasePayment(uint256 orderId) external onlyPoD {
        EscrowEntry storage e = escrows[orderId];
        if (e.payer == address(0)) revert EscrowNotFound();
        if (e.released) revert AlreadyReleased();

        e.released = true;
        if (e.tokenType == TokenType.ETH) {
            (bool sent, ) = e.payee.call{value: e.amount}("");
            if (!sent) revert TransferFailed();
        } else {
            if (!IERC20(e.token).transfer(e.payee, e.amount))
                revert TransferFailed();
        }

        emit PaymentReleased(orderId, e.payee, e.amount);
    }

    function refund(uint256 orderId) external {
        EscrowEntry storage e = escrows[orderId];
        if (e.payer == address(0)) revert EscrowNotFound();
        if (msg.sender != e.payer) revert NotOwner();
        if (e.released) revert AlreadyReleased();

        e.released = true;
        if (e.tokenType == TokenType.ETH) {
            (bool sent, ) = e.payer.call{value: e.amount}("");
            if (!sent) revert TransferFailed();
        } else {
            if (!IERC20(e.token).transfer(e.payer, e.amount))
                revert TransferFailed();
        }

        emit Refunded(orderId, e.payer, e.amount);
    }

    // 🔹 New Read Functions

    function getEscrow(
        uint256 orderId
    ) external view returns (EscrowEntry memory) {
        EscrowEntry memory e = escrows[orderId];
        if (e.payer == address(0)) revert EscrowNotFound();
        return e;
    }

    function isPaid(uint256 orderId) external view returns (bool) {
        EscrowEntry memory e = escrows[orderId];
        if (e.payer == address(0)) revert EscrowNotFound();
        return e.released;
    }

    function getPayer(uint256 orderId) external view returns (address) {
        EscrowEntry memory e = escrows[orderId];
        if (e.payer == address(0)) revert EscrowNotFound();
        return e.payer;
    }

    function getPayee(uint256 orderId) external view returns (address) {
        EscrowEntry memory e = escrows[orderId];
        if (e.payer == address(0)) revert EscrowNotFound();
        return e.payee;
    }

    function getAmount(uint256 orderId) external view returns (uint256) {
        EscrowEntry memory e = escrows[orderId];
        if (e.payer == address(0)) revert EscrowNotFound();
        return e.amount;
    }

    receive() external payable {}
}
