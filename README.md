# 📦 Decentralized Delivery & Payment System

This project implements a modular system for **delivery lifecycle management** with **escrow-based payments** and **proof-of-delivery verification**.
It ensures secure, transparent, and role-based logistics operations.

---

## 🔹 Contracts Overview

### 1. **AccessRegistry.sol**

Minimal **Role-Based Access Control (RBAC)** used by all other contracts.

* **Roles**:

  * `Admin` – System administrator
  * `FleetOwner` – Manages fleet & creates deliveries
  * `Carrier` – Assigned to execute deliveries
  * `ThirdPartyLogistics` – External logistics partners
  * `Customer` – End-user requesting deliveries

* **Core Functions**:

  * `grantRole(account, role)` → Assigns a role
  * `revokeRole(account, role)` → Removes a role
  * `hasRole(account, role)` → Checks if account has role
  * `transferOwnership(newOwner)` → Transfers ownership

---

### 2. **DeliveryManagement.sol**

Manages the **lifecycle of deliveries**.

* **Delivery Status**: `Created → InTransit → Delivered → Cancelled`

* **Core Functions**:

  * `createDelivery(truckId, origin, destination, eta)`

    * Only **FleetOwner** or **Carrier** can create
    * Generates a unique `orderId`
  * `assignCarrier(orderId, carrier)`

    * Assigns a carrier to the delivery
  * `setStatus(orderId, newStatus)`

    * Updates status (except Delivered)
  * `markDeliveredFromPoD(orderId)`

    * Only **ProofOfDelivery contract** can mark as Delivered
  * `getDelivery(orderId)` → Returns full delivery info

* **Events**:

  * `DeliveryCreated`, `CarrierAssigned`, `StatusUpdated`, `ProofOfDeliverySet`

---

### 3. **PaymentEscrow\.sol**

Handles **escrowed payments** between **payer (customer)** and **payee (carrier/fleet)**.

* **Supports**:

  * ETH payments
  * ERC20 token payments

* **Core Functions**:

  * `createEscrowETH(orderId, payee)` – Lock ETH for delivery
  * `createEscrowERC20(orderId, payee, token, amount)` – Lock ERC20 tokens
  * `releasePayment(orderId)` – Releases funds (only PoD contract)
  * `refund(orderId)` – Refund to payer (if not released)
  * Read-only helpers: `getEscrow`, `isPaid`, `getPayer`, `getPayee`, `getAmount`

* **Events**:

  * `EscrowCreated`, `PaymentReleased`, `Refunded`

---

### 4. **ProofOfDelivery.sol**

Provides a **checkpoint-based Proof of Delivery (PoD)** mechanism.

* **Workflow**:

  1. **Initialize proof** (`initProof`) for an order
  2. **Add checkpoints** (planned route locations & times)
  3. **Mark checkpoints reached** during transit
  4. **Finalize delivery**:

     * Calls `DeliveryManagement.markDeliveredFromPoD()`
     * Calls `PaymentEscrow.releasePayment()`

* **Core Functions**:

  * `createProofWithCheckpoints(orderId, lats, lons, times)` → Bulk checkpoint setup
  * `addCheckpoint(orderId, lat, lon, time)` → Add single checkpoint
  * `markCheckpointReached(orderId, index, actualTime)` → Mark progress
  * `finalizeDelivery(orderId, payee)` → Marks delivery as completed & triggers payment

* **Events**:

  * `ProofInitialized`, `CheckpointAdded`, `CheckpointReached`, `Finalized`

---

## 🔄 Contract Interactions

1. **Setup**

   * Deploy `AccessRegistry` → Set roles
   * Deploy `DeliveryManagement` (requires registry)
   * Deploy `PaymentEscrow`
   * Deploy `ProofOfDelivery` (requires registry, delivery, escrow)
   * Set PoD contract in `DeliveryManagement` & `PaymentEscrow`

2. **Delivery Lifecycle**

   * FleetOwner/Carrier → `createDelivery()`
   * Assign Carrier → `assignCarrier()`
   * Customer → `createEscrowETH/ERC20()` (locks funds)

3. **Proof of Delivery**

   * Admin/Carrier/FleetOwner → `createProofWithCheckpoints()`
   * As checkpoints are reached → `markCheckpointReached()`

4. **Finalization**

   * Carrier/Admin → `finalizeDelivery()`

     * Marks delivery as Delivered
     * Releases payment from escrow to payee

---

## ✅ Example Flow

1. Admin grants roles to FleetOwner, Carrier, Customer.
2. FleetOwner creates delivery:

   ```solidity
   createDelivery("TRUCK123", "Delhi", "Mumbai", 1750000000);
   ```
3. Customer locks funds:

   ```solidity
   createEscrowETH{value: 5 ether}(orderId, carrier);
   ```
4. Carrier adds checkpoints (route stops).
5. During transit, Carrier marks checkpoints as reached.
6. On delivery, Carrier/Admin finalizes:

   ```solidity
   finalizeDelivery(orderId, carrier);
   ```

   → Delivery marked as **Delivered**
   → Escrow releases payment to **Carrier**

---

## ⚡ Features

* 🔐 **Role-based security** via `AccessRegistry`
* 🚚 **End-to-end delivery tracking** with checkpoints
* 💰 **Secure payments** via escrow (ETH & ERC20)
* 🔗 **Cross-contract interaction** ensures payments only release on delivery proof
* 📜 **Transparent audit logs** through events

---

## 🛠 Deployment & Testing

```bash
# Compile
npx hardhat compile

# Deploy
npx hardhat run scripts/deploy.js --network <network>

# Run tests
npx hardhat test
```

---
