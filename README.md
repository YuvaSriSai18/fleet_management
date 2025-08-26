# 🚚 Delivery & Proof of Delivery (PoD) Smart Contracts

This project implements a **blockchain-based delivery tracking system** with two main contracts:

1. **DeliveryManagement** – Manages the lifecycle of deliveries (create, update, track status).
2. **ProofOfDelivery (PoD)** – Records GPS checkpoints for deliveries and finalizes them securely.

---

## ⚙️ How it Works

### **1. Delivery Creation**

* A delivery is created by any user (logistics company / admin).
* Each delivery stores:

  * `orderId` (auto-incremented)
  * `truckId` (identifier of the vehicle)
  * `origin` and `destination`
  * `ETA` (expected delivery time)
  * `createdBy` (the wallet that created it)
  * `status` (enum: Pending → InTransit → Delivered → Failed)

```solidity
orderId = deliveryManagement.createDelivery(truckId, origin, destination, eta);
```

---

### **2. Updating Delivery Status**

* Only two parties can update a delivery:

  1. The **creator** of the delivery.
  2. The **ProofOfDelivery contract** (when finalizing).

```solidity
deliveryManagement.updateDeliveryStatus(orderId, DeliveryStatus.InTransit);
```

---

### **3. Adding GPS Checkpoints (Proof Recording)**

* GPS checkpoints are added to the **PoD contract**.
* Each checkpoint includes:

  * `latitude`
  * `longitude`
  * `timestamp`

```solidity
proofOfDelivery.addCheckpoint(orderId, 1745243, 7845521, 1724672821);
```

➡️ When the **first checkpoint** is added, the proof is marked as *initialized*.

---

### **4. Finalizing a Delivery**

* Only the **PoD contract** can finalize a delivery.
* A delivery can only be finalized if:

  * At least one checkpoint exists (`proof.initialized == true`).

```solidity
proofOfDelivery.finalizeDelivery(orderId);
```

➡️ This will:

1. Set the delivery status to `Delivered`.
2. Emit an event `DeliveryFinalized`.

---

## 👥 Roles & Permissions

| Actor                           | Actions                                                           |
| ------------------------------- | ----------------------------------------------------------------- |
| **Creator (Logistics Company)** | - Create delivery<br>- Update delivery status manually (optional) |
| **ProofOfDelivery Contract**    | - Add checkpoints<br>- Finalize delivery (sets Delivered status)  |
| **Public**                      | - View deliveries & proofs (read-only)                            |

---

## 🚀 Example Flow

Let’s say **LogiTrans Pvt Ltd** is delivering goods from **Hyderabad → Bangalore** using `Truck-123`.

### Step 1: Create Delivery

```js
orderId = deliveryManagement.createDelivery(
  "Truck-123",
  "Hyderabad",
  "Bangalore",
  1724800000 // ETA
);
```

➡️ `orderId = 1` created with status `Pending`.

---

### Step 2: Add Checkpoints

Truck moves along the route → checkpoints are added.

```js
proofOfDelivery.addCheckpoint(1, 1745243, 7845521, 1724672821); // Hyderabad
proofOfDelivery.addCheckpoint(1, 1745300, 7846000, 1724680000); // En route
```

➡️ Proof initialized and checkpoints recorded.

---

### Step 3: Finalize Delivery

When the truck reaches Bangalore:

```js
proofOfDelivery.finalizeDelivery(1);
```

➡️ Delivery status automatically updated to **Delivered**.

---

## 📜 Events

* `DeliveryCreated(orderId, truckId, origin, destination, eta, createdBy)`
* `DeliveryStatusUpdated(orderId, newStatus, updatedAt)`
* `CheckpointAdded(orderId, latitude, longitude, timestamp)`
* `DeliveryFinalized(orderId, finalizedAt)`

---

✅ With this system:

* The **company** creates deliveries.
* The **PoD contract** ensures GPS proof exists before finalizing.
* No one can finalize a delivery without proof.

---


Perfect 🚀 now I see the **big picture**. You’re basically building the **blockchain layer of QuantumFleet** – 5 contracts that make logistics **tamper-proof, automated, and auditable**, while quantum optimization engines (Qiskit, D-Wave, etc.) feed real-time decisions to this layer.

Since you’ve already completed ✅ **1. DeliveryManagement** and ✅ **2. ProofOfDelivery**, let me frame everything as a **README/Project Overview** that explains **what each contract does, how they connect, who uses them, and how it fits into your QuantumFleet system.**

---

# 🛰️ QuantumFleet Blockchain Layer

### Securing Logistics with Blockchain + Quantum Optimization

---

## 🔹 Why Blockchain + Quantum?

Logistics suffers from delays, inefficiencies, and lack of trust between carriers, 3PLs, and customers.
QuantumFleet solves this with a **hybrid quantum-classical optimization engine** + **blockchain smart contracts**:

* **Quantum computing** → Optimizes routes, load balancing, fleet utilization.
* **Blockchain** → Secures shipment data, automates payments, enables transparent 3PL collaboration.
* **Integration** → APIs connect live telematics, GPS/GIS data, and quantum solvers with blockchain records.

---

## 📦 Smart Contract Modules

### **1. Delivery Management Contract (Core)** ✅ Done

**Purpose:** Immutable record of shipments.

* `createDelivery(orderId, truckId, origin, destination, eta)` → Create delivery.
* `updateDeliveryStatus(orderId, status)` → Update status (Created, InTransit, Delivered, Cancelled).
* `getDelivery(orderId)` → Fetch delivery details.

**Events:**

* `DeliveryCreated`
* `DeliveryStatusUpdated`

✅ Guarantees transparent, tamper-proof shipment records.

---

### **2. Proof of Delivery (PoD) Contract** ✅ Done

**Purpose:** Secure completion verification via geofencing/GPS.

* `addCheckpoint(orderId, lat, long, timestamp)` → Log GPS checkpoint.
* `finalizeDelivery(orderId)` → Mark delivery complete, syncs with DeliveryManagement.

**Events:**

* `CheckpointAdded`
* `DeliveryFinalized`

✅ Provides auditable delivery verification for compliance & SLAs.

---

### **3. Capacity Sharing & Load Exchange Contract** ⏳ Next

**Purpose:** Enable 3PL collaboration by sharing unused truck space.

* `listCapacity(truckId, capacity, route, price)` → Advertise available capacity.
* `bookCapacity(truckId, buyer, loadSize)` → Reserve capacity.
* `cancelBooking(truckId, bookingId)` → Cancel booking.

**Events:**

* `CapacityListed`
* `CapacityBooked`
* `BookingCancelled`

✅ Encourages collaboration, improves fleet utilization, reduces empty runs.

---

### **4. Payment & SLA Smart Contract** ⏳ Next

**Purpose:** Automates payments & penalties.

* `createEscrow(orderId, payer, payee, amount)` → Hold funds.
* `releasePayment(orderId)` → Transfer funds once delivered.
* `applyPenalty(orderId, reason, penaltyAmount)` → Deduct for SLA violations.

**Events:**

* `EscrowCreated`
* `PaymentReleased`
* `PenaltyApplied`

✅ Trustless settlement, no disputes.

---

### **5. Stakeholder Identity & Access Contract** ⏳ Next

**Purpose:** Role-based access control.

* `registerUser(address, role)` → Register stakeholder (Fleet Owner, Carrier, 3PL, Customer).
* `getUserRole(address)` → Fetch role.
* `grantRole(address, role)` / `revokeRole(address, role)` → Admin controls.

✅ Prevents unauthorized access; ensures only valid actors can update records.

---

## 🔄 Example Workflow

Let’s say **LogiTrans Pvt Ltd** delivers **Hyderabad → Bangalore**:

1. **Delivery Created**

   ```solidity
   deliveryManagement.createDelivery("Truck-123", "Hyderabad", "Bangalore", 1724800000);
   ```

   → Status = `Created`.

2. **Route Optimization (Quantum Layer)**
   QuantumFleet engine (QAOA/D-Wave) optimizes truck route & load distribution.

3. **Proof-of-Delivery Checkpoints**

   ```solidity
   proofOfDelivery.addCheckpoint(1, 1745243, 7845521, 1724672821); // Hyderabad
   proofOfDelivery.addCheckpoint(1, 1745300, 7846000, 1724680000); // En route
   ```

   → Blockchain records GPS logs.

4. **Delivery Finalized**

   ```solidity
   proofOfDelivery.finalizeDelivery(1);
   ```

   → Status = `Delivered`, PoD stored.

5. **Payment Released (Escrow)**

   ```solidity
   paymentContract.releasePayment(1);
   ```

   → Carrier gets paid, automatically.

---

## 👥 Stakeholder Roles

| Role            | Capabilities                           |
| --------------- | -------------------------------------- |
| **Fleet Owner** | Create deliveries, list truck capacity |
| **Carrier**     | Add checkpoints, finalize deliveries   |
| **3PL**         | Book spare capacity, track shipments   |
| **Customer**    | View delivery status, payments         |
| **Admin**       | Manage user roles, ensure compliance   |

---

## 🌍 Benefits

* **Economic** → Reduced costs via optimized routes & shared capacity.
* **Social** → Collaboration between carriers & 3PLs.
* **Environmental** → Lower emissions, fewer empty runs.
* **Technological** → Future-proof logistics using quantum + blockchain.

---

👉 This README sets the foundation.
Since you’ve **done 1 & 2 already**, the next natural step is **3. Capacity Sharing Contract**.

Do you want me to draft a **Solidity skeleton for Capacity Sharing (3)**, aligned with your 1 & 2 contracts, so it plugs in smoothly?
