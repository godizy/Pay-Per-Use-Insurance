# 🛡️ Pay-Per-Use Insurance Smart Contract

A revolutionary micro-insurance platform on the Stacks blockchain that provides coverage only when you need it! Perfect for flight delays, gadget rentals, and other temporary coverage needs. 🚀

## ✨ Features

- 🎯 **Micro-Insurance Policies**: Create insurance policies for specific time periods and coverage amounts
- ⚡ **Instant Activation**: Policies activate immediately upon creation with STX payment
- 🔍 **Oracle-Based Claims**: Automated claim processing through authorized oracles
- 💰 **Flexible Coverage**: Support for various policy types (flight delays, rental protection, etc.)
- 📊 **Real-Time Statistics**: Track total premiums, claims, and contract performance
- 🔧 **Policy Management**: Cancel, extend, or modify policies as needed

## 🏗️ Contract Architecture

The contract manages:
- **Policies**: Time-based insurance coverage with premiums and metadata
- **Claims**: Submitted claims with evidence and oracle-based processing
- **Oracles**: Authorized third parties that can approve/reject claims
- **Statistics**: Contract-wide metrics for transparency

## 🚀 Usage Instructions

### Creating a Policy

```clarity
(contract-call? .Pay-Per-Use-Insurance create-policy 
  "flight-delay"     ; policy type
  u1000000          ; premium (1 STX in microstx)
  u10000000         ; coverage amount (10 STX)
  u1440             ; duration in blocks (~10 days)
  "Flight ABC123 - NYC to LAX") ; metadata
```

### Submitting a Claim

```clarity
(contract-call? .Pay-Per-Use-Insurance submit-claim
  u1                ; policy ID
  u5000000          ; claim amount (5 STX)
  "delay-claim"     ; claim type
  "Flight delayed 4 hours due to weather") ; evidence
```

### Processing Claims (Oracle Only)

```clarity
(contract-call? .Pay-Per-Use-Insurance process-claim
  u1     ; claim ID
  true)  ; approved (true/false)
```

## 📋 Policy Types Examples

- 🛫 **Flight Delays**: Coverage for delayed or cancelled flights
- 📱 **Gadget Rental**: Protection for rented electronics
- 🏠 **Short-term Property**: Temporary accommodation insurance
- 🚗 **Vehicle Rental**: Car rental protection
- 📦 **Package Delivery**: Shipping delay coverage

## 🔍 Read-Only Functions

### Get Policy Information
```clarity
(contract-call? .Pay-Per-Use-Insurance get-policy u1)
```

### Check Policy Status
```clarity
(contract-call? .Pay-Per-Use-Insurance get-policy-status u1)
```

### View Contract Statistics
```clarity
(contract-call? .Pay-Per-Use-Insurance get-contract-stats)
```

### Calculate Premium
```clarity
(contract-call? .Pay-Per-Use-Insurance calculate-premium
  u10000000  ; coverage amount
  u1440      ; duration
  u150)      ; risk factor
```

## 🔒 Admin Functions

### Authorize Oracle
```clarity
(contract-call? .Pay-Per-Use-Insurance authorize-oracle 'SP1ABC123...)
```

### Set New Owner
```clarity
(contract-call? .Pay-Per-Use-Insurance set-contract-owner 'SP1XYZ789...)
```

## 💡 How It Works

1. **Policy Creation** 📝: Users pay a premium and create a policy with specific coverage terms
2. **Activation** ⚡: Policy becomes active immediately for the specified duration
3. **Claim Submission** 📤: Users submit claims with evidence during the policy period
4. **Oracle Review** 👨‍⚖️: Authorized oracles review evidence and approve/reject claims
5. **Payout** 💸: Approved claims are automatically paid from the contract balance

## ⚠️ Important Notes

- Policies must be created with a premium > 0 STX
- Claims can only be submitted during the active policy period
- Only authorized oracles can process claims
- Policy cancellation provides a 50% premium refund
- Policy extension costs 25% of the original premium

## 🛠️ Development

### Prerequisites
- Clarinet CLI installed
- Stacks wallet for testing

### Testing
```bash
clarinet check
npm install
npm test
```

### Deployment
```bash
clarinet deploy
```

## 📊 Contract Statistics

The contract tracks:
- Total number of policies created
- Total premiums collected
- Total claims processed and paid
- Current contract balance
- Active policy count

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📄 License

This project is licensed under the MIT License.

---

Built with ❤️ on Stacks blockchain | Ready for micro-insurance revolution! 🚀
