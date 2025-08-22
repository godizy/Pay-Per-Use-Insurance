;; Pay-Per-Use Insurance Smart Contract

(define-constant ERR-NOT-AUTHORIZED (err u1001))
(define-constant ERR-INVALID-POLICY (err u1002))
(define-constant ERR-INSUFFICIENT-FUNDS (err u1003))
(define-constant ERR-POLICY-NOT-FOUND (err u1004))
(define-constant ERR-CLAIM-ALREADY-PROCESSED (err u1005))
(define-constant ERR-POLICY-EXPIRED (err u1006))
(define-constant ERR-INVALID-CLAIM (err u1007))
(define-constant ERR-ORACLE-NOT-AUTHORIZED (err u1008))

(define-data-var contract-owner principal tx-sender)
(define-data-var next-policy-id uint u1)
(define-data-var total-premiums uint u0)
(define-data-var total-claims-paid uint u0)

(define-map policies
  { policy-id: uint }
  {
    insured: principal,
    policy-type: (string-ascii 50),
    premium: uint,
    coverage-amount: uint,
    start-block: uint,
    end-block: uint,
    active: bool,
    metadata: (string-ascii 200)
  }
)

(define-map claims
  { claim-id: uint }
  {
    policy-id: uint,
    claimant: principal,
    amount: uint,
    claim-type: (string-ascii 50),
    status: (string-ascii 20),
    submitted-block: uint,
    processed-block: (optional uint),
    evidence: (string-ascii 300)
  }
)

(define-map authorized-oracles principal bool)

(define-data-var next-claim-id uint u1)

(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (var-set contract-owner new-owner))
  )
)

(define-public (authorize-oracle (oracle principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-oracles oracle true))
  )
)

(define-public (revoke-oracle (oracle principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-oracles oracle false))
  )
)

(define-public (create-policy 
  (policy-type (string-ascii 50))
  (premium uint)
  (coverage-amount uint)
  (duration uint)
  (metadata (string-ascii 200)))
  (let
    (
      (policy-id (var-get next-policy-id))
      (current-block stacks-block-height)
    )
    (asserts! (> premium u0) ERR-INSUFFICIENT-FUNDS)
    (asserts! (> coverage-amount u0) ERR-INVALID-POLICY)
    (asserts! (> duration u0) ERR-INVALID-POLICY)
    
    (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
    
    (map-set policies
      { policy-id: policy-id }
      {
        insured: tx-sender,
        policy-type: policy-type,
        premium: premium,
        coverage-amount: coverage-amount,
        start-block: current-block,
        end-block: (+ current-block duration),
        active: true,
        metadata: metadata
      }
    )
    
    (var-set next-policy-id (+ policy-id u1))
    (var-set total-premiums (+ (var-get total-premiums) premium))
    
    (ok policy-id)
  )
)

(define-public (submit-claim
  (policy-id uint)
  (claim-amount uint)
  (claim-type (string-ascii 50))
  (evidence (string-ascii 300)))
  (let
    (
      (policy (unwrap! (map-get? policies { policy-id: policy-id }) ERR-POLICY-NOT-FOUND))
      (claim-id (var-get next-claim-id))
      (current-block stacks-block-height)
    )
    (asserts! (is-eq tx-sender (get insured policy)) ERR-NOT-AUTHORIZED)
    (asserts! (get active policy) ERR-INVALID-POLICY)
    (asserts! (< current-block (get end-block policy)) ERR-POLICY-EXPIRED)
    (asserts! (<= claim-amount (get coverage-amount policy)) ERR-INVALID-CLAIM)
    
    (map-set claims
      { claim-id: claim-id }
      {
        policy-id: policy-id,
        claimant: tx-sender,
        amount: claim-amount,
        claim-type: claim-type,
        status: "pending",
        submitted-block: current-block,
        processed-block: none,
        evidence: evidence
      }
    )
    
    (var-set next-claim-id (+ claim-id u1))
    
    (ok claim-id)
  )
)

(define-public (process-claim (claim-id uint) (approved bool))
  (let
    (
      (claim (unwrap! (map-get? claims { claim-id: claim-id }) ERR-INVALID-CLAIM))
      (policy (unwrap! (map-get? policies { policy-id: (get policy-id claim) }) ERR-POLICY-NOT-FOUND))
      (current-block stacks-block-height)
    )
    (asserts! (default-to false (map-get? authorized-oracles tx-sender)) ERR-ORACLE-NOT-AUTHORIZED)
    (asserts! (is-eq (get status claim) "pending") ERR-CLAIM-ALREADY-PROCESSED)
    
    (if approved
      (begin
        (try! (as-contract (stx-transfer? (get amount claim) tx-sender (get claimant claim))))
        (var-set total-claims-paid (+ (var-get total-claims-paid) (get amount claim)))
        (map-set claims
          { claim-id: claim-id }
          (merge claim { status: "approved", processed-block: (some current-block) })
        )
      )
      (map-set claims
        { claim-id: claim-id }
        (merge claim { status: "rejected", processed-block: (some current-block) })
      )
    )
    
    (ok approved)
  )
)

(define-public (cancel-policy (policy-id uint))
  (let
    (
      (policy (unwrap! (map-get? policies { policy-id: policy-id }) ERR-POLICY-NOT-FOUND))
      (current-block stacks-block-height)
      (refund-amount (/ (get premium policy) u2))
    )
    (asserts! (is-eq tx-sender (get insured policy)) ERR-NOT-AUTHORIZED)
    (asserts! (get active policy) ERR-INVALID-POLICY)
    (asserts! (< current-block (get end-block policy)) ERR-POLICY-EXPIRED)
    
    (map-set policies
      { policy-id: policy-id }
      (merge policy { active: false })
    )
    
    (try! (as-contract (stx-transfer? refund-amount tx-sender (get insured policy))))
    
    (ok refund-amount)
  )
)

(define-public (extend-policy (policy-id uint) (additional-duration uint))
  (let
    (
      (policy (unwrap! (map-get? policies { policy-id: policy-id }) ERR-POLICY-NOT-FOUND))
      (extension-fee (/ (get premium policy) u4))
    )
    (asserts! (is-eq tx-sender (get insured policy)) ERR-NOT-AUTHORIZED)
    (asserts! (get active policy) ERR-INVALID-POLICY)
    (asserts! (> additional-duration u0) ERR-INVALID-POLICY)
    
    (try! (stx-transfer? extension-fee tx-sender (as-contract tx-sender)))
    
    (map-set policies
      { policy-id: policy-id }
      (merge policy { end-block: (+ (get end-block policy) additional-duration) })
    )
    
    (var-set total-premiums (+ (var-get total-premiums) extension-fee))
    
    (ok (get end-block (merge policy { end-block: (+ (get end-block policy) additional-duration) })))
  )
)

(define-read-only (get-policy (policy-id uint))
  (map-get? policies { policy-id: policy-id })
)

(define-read-only (get-claim (claim-id uint))
  (map-get? claims { claim-id: claim-id })
)

(define-read-only (get-contract-stats)
  {
    total-policies: (- (var-get next-policy-id) u1),
    total-claims: (- (var-get next-claim-id) u1),
    total-premiums: (var-get total-premiums),
    total-claims-paid: (var-get total-claims-paid),
    contract-balance: (stx-get-balance (as-contract tx-sender))
  }
)

(define-read-only (is-policy-active (policy-id uint))
  (match (map-get? policies { policy-id: policy-id })
    policy (and 
             (get active policy)
             (< stacks-block-height (get end-block policy)))
    false
  )
)

(define-read-only (get-policy-status (policy-id uint))
  (match (map-get? policies { policy-id: policy-id })
    policy 
      (if (get active policy)
        (if (< stacks-block-height (get end-block policy))
          "active"
          "expired")
        "cancelled")
    "not-found"
  )
)

(define-read-only (calculate-premium (coverage-amount uint) (duration uint) (risk-factor uint))
  (let
    (
      (base-rate u100)
      (duration-multiplier (/ duration u144))
      (risk-multiplier risk-factor)
    )
    (/ (* (* coverage-amount base-rate) duration-multiplier risk-multiplier) u1000000)
  )
)

(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

(define-read-only (is-authorized-oracle (oracle principal))
  (default-to false (map-get? authorized-oracles oracle))
)
