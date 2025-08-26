## 🔹 1. **Delivery Management Contract** - imp

**Purpose**: Create immutable records of shipments, trucks, and routes.
**Functions**:

* `createDelivery(orderId, truckId, origin, destination, eta)` → store a new delivery.
* `updateDeliveryStatus(orderId, status)` → update status (Created, In-Transit, Delivered, Cancelled).
* `getDelivery(orderId)` → fetch delivery details.
  **Events**: `DeliveryCreated`, `DeliveryStatusUpdated`.
  ✅ Ensures all delivery events are tamper-proof.

---

## 🔹 2. **Proof of Delivery (PoD) Contract** - imp

**Purpose**: Securely record completion of deliveries using geofencing/GPS checkpoints.
**Functions**:

* `addCheckpoint(orderId, lat, long, timestamp)` → log checkpoint.
* `finalizeDelivery(orderId)` → mark delivery as completed.
  **Events**: `CheckpointAdded`, `DeliveryFinalized`.
  ✅ Provides verifiable proof of delivery for audit & compliance.

---

## 🔹 3. **Capacity Sharing & Load Exchange Contract**

**Purpose**: Let carriers advertise unused truck capacity and allow 3PLs to book it.
**Functions**:

* `listCapacity(truckId, capacity, route, price)` → advertise free space.
* `bookCapacity(truckId, buyer, loadSize)` → reserve capacity.
* `cancelBooking(truckId, bookingId)` → cancel if needed.
  **Events**: `CapacityListed`, `CapacityBooked`, `BookingCancelled`.
  ✅ Encourages collaboration and maximizes truck utilization.

---

## 🔹 4. **Payment & SLA Smart Contract** - imp

**Purpose**: Automate payments once deliveries are verified.
**Functions**:

* `createEscrow(orderId, payer, payee, amount)` → hold funds in contract.
* `releasePayment(orderId)` → transfer funds to carrier upon delivery.
* `applyPenalty(orderId, reason, penaltyAmount)` → deduct from escrow if SLA violated (e.g., late).
  **Events**: `EscrowCreated`, `PaymentReleased`, `PenaltyApplied`.
  ✅ Builds trust with automatic settlement, no disputes.

---

## 🔹 5. **Stakeholder Identity & Access Contract**

**Purpose**: Manage roles (Fleet Owner, Carrier, 3PL, Customer).
**Functions**:

* `registerUser(address, role)` → register stakeholder.
* `getUserRole(address)` → check role.
* `grantRole(address, role)` / `revokeRole(address, role)` → admin control.
  ✅ Prevents unauthorized updates; ensures only valid actors interact.

---

### 🌍 Why these 5 Contracts?

* **Delivery Contract** → core record system.
* **PoD Contract** → real-world trust + compliance.
* **Capacity Sharing Contract** → collaboration across 3PLs.
* **Payment Contract** → removes disputes with automation.
* **Identity Contract** → security + access control.
