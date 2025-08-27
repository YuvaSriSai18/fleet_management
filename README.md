# 🚚 Fleet Delivery + Escrow System – Overview

This system is built with **four smart contracts** that work together to manage delivery orders, track proof of delivery, and handle payments securely via escrow.

---

## 1. **AccessRegistry.sol**

### Purpose

* Acts as the **role manager** for the system.
* Controls who can perform critical actions (FleetOwner, Carrier, Customer).

### Key Features

* `assignRole(address, Role)` – Owner assigns a role.
* `revokeRole(address, Role)` – Owner revokes a role.
* `hasRole(address, Role)` – Used by other contracts to validate permissions.

### Why it matters

All other contracts **trust AccessRegistry** to know “who is who”.

---

## 2. **DeliveryManagement.sol**

### Purpose

* Manages **delivery lifecycle** (Created → InTransit → Delivered → Cancelled).
* Enforces that only `ProofOfDelivery` can finalize delivery.

### Key Functions

* `createDelivery(orderId, customer, carrier)` – Registers a delivery.
* `updateStatus(orderId, Status)` – Changes state (except Delivered).
* `markDeliveredFromPoD(orderId)` – Marks a delivery Delivered when PoD finalizes.

### Why it matters

This contract is the **source of truth** for the state of each order.
It also acts as the bridge between **ProofOfDelivery** and **Escrow**.

---

## 3. **ProofOfDelivery.sol**

### Purpose

* Records GPS checkpoints and allows **finalization** of delivery.
* When finalized, it tells `DeliveryManagement` to mark the order as Delivered.

### Key Functions

* `addCheckpoint(orderId, lat, lon, ts)` – Logs location updates.
* `finalize(orderId)` – Finalizes proof and triggers delivery completion.
* `getCheckpoints(orderId)` – View checkpoints.

### Why it matters

Ensures that **only authorized actors** (FleetOwner/Carrier) can finalize delivery, preventing fraud.

---

## 4. **Escrow\.sol (PaymentEscrow)**

### Purpose

* Holds funds until delivery is completed.
* Releases payment automatically once Delivery is finalized.

### Key Functions

* `createEscrowETH(orderId, payee)` – Customer deposits ETH.
* `createEscrowERC20(orderId, token, payee, amount)` – Deposit tokens.
* `releasePayment(orderId)` – Sends funds to Carrier (only callable by Delivery contract).
* `refund(orderId)` – Allows payer to reclaim funds before delivery.
* `applyPenalty(orderId, penalty)` – Admin can reduce payment for violations.

### Why it matters

Protects both **customers** and **carriers** by ensuring money is only transferred if delivery is successful.

---

## 🔗 How They Work Together

Here’s the flow:

1. **Setup Roles**

   * Owner assigns roles via `AccessRegistry` (FleetOwner, Carrier, Customer).

2. **Create Delivery**

   * FleetOwner calls `createDelivery` in `DeliveryManagement`.
   * Customer simultaneously funds escrow via `createEscrowETH`.

3. **In Transit**

   * Carrier updates checkpoints in `ProofOfDelivery`. (Optional)

4. **Finalize Delivery**

   * Carrier/FleetOwner calls `finalize(orderId)` in PoD.
   * PoD → calls `markDeliveredFromPoD(orderId)` in DeliveryManagement.
   * DeliveryManagement → calls `releasePayment(orderId)` in Escrow.
   * Escrow → pays Carrier.

---

## 🔧 Deployment & Connection Steps

1. **Deploy AccessRegistry**
   Save address.

2. **Deploy DeliveryManagement** (pass AccessRegistry address).
   Save address.

3. **Deploy ProofOfDelivery** (pass AccessRegistry + DeliveryManagement).
   Call `DeliveryManagement.setProofOfDelivery(podAddress)`.

4. **Deploy Escrow** (pass DeliveryManagement address).
   Call `DeliveryManagement.setEscrow(escrowAddress)` if you extend it.

Now all 4 contracts are connected.

---

## 🌐 Frontend Integration

From frontend (React + ethers.js):

### 1. Connect to Contracts

```js
import { ethers } from "ethers";
import AccessABI from "./abis/AccessRegistry.json";
import DeliveryABI from "./abis/DeliveryManagement.json";
import PodABI from "./abis/ProofOfDelivery.json";
import EscrowABI from "./abis/Escrow.json";

const provider = new ethers.BrowserProvider(window.ethereum);
const signer = await provider.getSigner();

const access = new ethers.Contract(ACCESS_ADDR, AccessABI, signer);
const delivery = new ethers.Contract(DELIVERY_ADDR, DeliveryABI, signer);
const pod = new ethers.Contract(POD_ADDR, PodABI, signer);
const escrow = new ethers.Contract(ESCROW_ADDR, EscrowABI, signer);
```

### 2. Example Actions

* **Customer funds escrow:**

```js
await escrow.createEscrowETH(orderId, carrierAddr, { value: ethers.parseEther("1.0") });
```

* **Carrier finalizes delivery:**

```js
await pod.finalize(orderId);
```

* **Listen for events:**

```js
escrow.on("EscrowReleased", (orderId, amount, to) => {
  console.log("Payment sent:", orderId, amount, to);
});
```

---
