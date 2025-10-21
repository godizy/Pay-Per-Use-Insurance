;; Pay-Per-Use Insurance Smart Contract

(define-constant ERR-NOT-AUTHORIZED (err u1001))
(define-constant ERR-INVALID-POLICY (err u1002))
(define-constant ERR-INSUFFICIENT-FUNDS (err u1003))
(define-constant ERR-POLICY-NOT-FOUND (err u1004))
(define-constant ERR-CLAIM-ALREADY-PROCESSED (err u1005))
(define-constant ERR-POLICY-EXPIRED (err u1006))
(define-constant ERR-INVALID-CLAIM (err u1007))
(define-constant ERR-ORACLE-NOT-AUTHORIZED (err u1008))
(define-constant ERR-RISK-PROFILE-NOT-FOUND (err u1009))
(define-constant ERR-BUNDLE-NOT-FOUND (err u1010))
(define-constant ERR-BUNDLE-ALREADY-EXISTS (err u1011))
(define-constant ERR-INVALID-BUNDLE (err u1012))
(define-constant ERR-MAX-POLICIES-REACHED (err u1013))

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

(define-map user-risk-profiles
  { user: principal }
  {
    base-risk-score: uint,
    total-policies: uint,
    total-claims: uint,
    approved-claims: uint,
    rejected-claims: uint,
    total-premiums-paid: uint,
    last-claim-block: uint,
    payment-reliability: uint,
    claim-frequency: uint,
    last-updated: uint
  }
)

(define-map policy-bundles
  { bundle-id: uint }
  {
    owner: principal,
    policy-ids: (list 10 uint),
    total-premium: uint,
    total-coverage: uint,
    bundle-discount: uint,
    created-block: uint,
    active: bool,
    bundle-name: (string-ascii 100)
  }
)

(define-map user-bundles
  { user: principal }
  { bundle-ids: (list 20 uint) }
)

(define-data-var next-claim-id uint u1)
(define-data-var next-bundle-id uint u1)

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
    
    (update-risk-profile-on-policy tx-sender premium)
    
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
        (update-risk-profile-on-claim (get claimant claim) true)
      )
      (begin
        (map-set claims
          { claim-id: claim-id }
          (merge claim { status: "rejected", processed-block: (some current-block) })
        )
        (update-risk-profile-on-claim (get claimant claim) false)
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

(define-private (update-risk-profile-on-policy (user principal) (premium uint))
  (let
    (
      (current-profile (default-to
        {
          base-risk-score: u100,
          total-policies: u0,
          total-claims: u0,
          approved-claims: u0,
          rejected-claims: u0,
          total-premiums-paid: u0,
          last-claim-block: u0,
          payment-reliability: u100,
          claim-frequency: u0,
          last-updated: stacks-block-height
        }
        (map-get? user-risk-profiles { user: user })
      ))
    )
    (map-set user-risk-profiles
      { user: user }
      (merge current-profile {
        total-policies: (+ (get total-policies current-profile) u1),
        total-premiums-paid: (+ (get total-premiums-paid current-profile) premium),
        last-updated: stacks-block-height
      })
    )
  )
)

(define-private (update-risk-profile-on-claim (user principal) (approved bool))
  (let
    (
      (current-profile (unwrap-panic (map-get? user-risk-profiles { user: user })))
      (new-total-claims (+ (get total-claims current-profile) u1))
      (new-approved-claims (if approved (+ (get approved-claims current-profile) u1) (get approved-claims current-profile)))
      (new-rejected-claims (if approved (get rejected-claims current-profile) (+ (get rejected-claims current-profile) u1)))
      (claim-rate (if (> new-total-claims u0) (/ (* new-approved-claims u100) new-total-claims) u0))
      (blocks-since-last-claim (- stacks-block-height (get last-claim-block current-profile)))
      (frequency-score (if (and (> (get last-claim-block current-profile) u0) (< blocks-since-last-claim u1440)) u150 u100))
    )
    (map-set user-risk-profiles
      { user: user }
      (merge current-profile {
        total-claims: new-total-claims,
        approved-claims: new-approved-claims,
        rejected-claims: new-rejected-claims,
        last-claim-block: stacks-block-height,
        claim-frequency: frequency-score,
        last-updated: stacks-block-height
      })
    )
  )
)

(define-read-only (calculate-dynamic-risk-score (user principal))
  (match (map-get? user-risk-profiles { user: user })
    profile (let
      (
        (base-score (get base-risk-score profile))
        (total-claims (get total-claims profile))
        (approved-claims (get approved-claims profile))
        (claim-rate (if (> total-claims u0) (/ (* approved-claims u100) total-claims) u0))
        (frequency-multiplier (get claim-frequency profile))
        (reliability-score (get payment-reliability profile))
        
        (claim-penalty (if (> claim-rate u20) (+ u50 (* (- claim-rate u20) u2)) u0))
        (frequency-penalty (if (> frequency-multiplier u100) (- frequency-multiplier u100) u0))
        (reliability-bonus (if (> reliability-score u90) (- u100 reliability-score) u0))
        
        (adjusted-score (+ base-score claim-penalty frequency-penalty (- reliability-bonus)))
      )
      (if (> adjusted-score u300) u300 (if (< adjusted-score u50) u50 adjusted-score))
    )
    u100
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

(define-read-only (calculate-personalized-premium (user principal) (coverage-amount uint) (duration uint))
  (let
    (
      (base-rate u100)
      (duration-multiplier (/ duration u144))
      (dynamic-risk-score (calculate-dynamic-risk-score user))
    )
    (/ (* (* coverage-amount base-rate) duration-multiplier dynamic-risk-score) u1000000)
  )
)

(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

(define-read-only (is-authorized-oracle (oracle principal))
  (default-to false (map-get? authorized-oracles oracle))
)

(define-read-only (get-user-risk-profile (user principal))
  (map-get? user-risk-profiles { user: user })
)

(define-read-only (get-user-risk-score (user principal))
  (calculate-dynamic-risk-score user)
)

(define-read-only (get-risk-tier (user principal))
  (let
    (
      (risk-score (calculate-dynamic-risk-score user))
    )
    (if (<= risk-score u75)
      "low-risk"
      (if (<= risk-score u125)
        "medium-risk"
        "high-risk"
      )
    )
  )
)

(define-read-only (calculate-premium-discount (user principal))
  (let
    (
      (risk-score (calculate-dynamic-risk-score user))
      (base-score u100)
    )
    (if (< risk-score base-score)
      (- base-score risk-score)
      u0
    )
  )
)

(define-public (create-policy-bundle
  (policy-ids (list 10 uint))
  (bundle-name (string-ascii 100)))
  (let
    (
      (bundle-id (var-get next-bundle-id))
      (current-block stacks-block-height)
      (num-policies (len policy-ids))
    )
    (asserts! (> num-policies u1) ERR-INVALID-BUNDLE)
    (asserts! (<= num-policies u10) ERR-MAX-POLICIES-REACHED)
    (asserts! (validate-bundle-ownership tx-sender policy-ids) ERR-NOT-AUTHORIZED)
    (asserts! (validate-bundle-policies policy-ids) ERR-INVALID-POLICY)
    
    (let
      (
        (bundle-stats (calculate-bundle-stats policy-ids))
        (discount-percent (calculate-bundle-discount num-policies))
        (discount-amount (/ (* (get total-premium bundle-stats) discount-percent) u100))
      )
      (map-set policy-bundles
        { bundle-id: bundle-id }
        {
          owner: tx-sender,
          policy-ids: policy-ids,
          total-premium: (get total-premium bundle-stats),
          total-coverage: (get total-coverage bundle-stats),
          bundle-discount: discount-amount,
          created-block: current-block,
          active: true,
          bundle-name: bundle-name
        }
      )
      
      (update-user-bundles tx-sender bundle-id)
      (var-set next-bundle-id (+ bundle-id u1))
      
      (ok bundle-id)
    )
  )
)

(define-public (deactivate-bundle (bundle-id uint))
  (let
    (
      (bundle (unwrap! (map-get? policy-bundles { bundle-id: bundle-id }) ERR-BUNDLE-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get owner bundle)) ERR-NOT-AUTHORIZED)
    (asserts! (get active bundle) ERR-INVALID-BUNDLE)
    
    (map-set policy-bundles
      { bundle-id: bundle-id }
      (merge bundle { active: false })
    )
    
    (ok true)
  )
)

(define-private (validate-bundle-ownership (owner principal) (policy-ids (list 10 uint)))
  (fold check-policy-owner policy-ids true)
)

(define-private (check-policy-owner (policy-id uint) (valid bool))
  (if valid
    (match (map-get? policies { policy-id: policy-id })
      policy (is-eq tx-sender (get insured policy))
      false
    )
    false
  )
)

(define-private (validate-bundle-policies (policy-ids (list 10 uint)))
  (fold check-policy-active policy-ids true)
)

(define-private (check-policy-active (policy-id uint) (valid bool))
  (if valid
    (match (map-get? policies { policy-id: policy-id })
      policy (get active policy)
      false
    )
    false
  )
)

(define-private (calculate-bundle-stats (policy-ids (list 10 uint)))
  (fold accumulate-policy-stats policy-ids { total-premium: u0, total-coverage: u0 })
)

(define-private (accumulate-policy-stats (policy-id uint) (stats { total-premium: uint, total-coverage: uint }))
  (match (map-get? policies { policy-id: policy-id })
    policy
      {
        total-premium: (+ (get total-premium stats) (get premium policy)),
        total-coverage: (+ (get total-coverage stats) (get coverage-amount policy))
      }
    stats
  )
)

(define-private (calculate-bundle-discount (num-policies uint))
  (if (<= num-policies u2)
    u5
    (if (<= num-policies u4)
      u10
      (if (<= num-policies u7)
        u15
        u20
      )
    )
  )
)

(define-private (update-user-bundles (user principal) (bundle-id uint))
  (let
    (
      (current-bundles (default-to { bundle-ids: (list) } (map-get? user-bundles { user: user })))
      (current-list (get bundle-ids current-bundles))
    )
    (map-set user-bundles
      { user: user }
      { bundle-ids: (unwrap-panic (as-max-len? (append current-list bundle-id) u20)) }
    )
  )
)

(define-read-only (get-policy-bundle (bundle-id uint))
  (map-get? policy-bundles { bundle-id: bundle-id })
)

(define-read-only (get-user-bundles (user principal))
  (map-get? user-bundles { user: user })
)

(define-read-only (calculate-bundle-savings (policy-ids (list 10 uint)))
  (let
    (
      (num-policies (len policy-ids))
      (bundle-stats (calculate-bundle-stats policy-ids))
      (discount-percent (calculate-bundle-discount num-policies))
      (discount-amount (/ (* (get total-premium bundle-stats) discount-percent) u100))
    )
    (ok {
      original-premium: (get total-premium bundle-stats),
      discount-percent: discount-percent,
      discount-amount: discount-amount,
      final-premium: (- (get total-premium bundle-stats) discount-amount),
      total-coverage: (get total-coverage bundle-stats)
    })
  )
)

(define-read-only (get-bundle-summary (bundle-id uint))
  (match (map-get? policy-bundles { bundle-id: bundle-id })
    bundle
      (ok {
        owner: (get owner bundle),
        num-policies: (len (get policy-ids bundle)),
        total-premium: (get total-premium bundle),
        total-coverage: (get total-coverage bundle),
        savings: (get bundle-discount bundle),
        active: (get active bundle),
        bundle-name: (get bundle-name bundle)
      })
    ERR-BUNDLE-NOT-FOUND
  )
)

(define-read-only (get-user-bundle-stats (user principal))
  (match (map-get? user-bundles { user: user })
    bundles
      (ok {
        total-bundles: (len (get bundle-ids bundles)),
        bundle-ids: (get bundle-ids bundles)
      })
    (ok { total-bundles: u0, bundle-ids: (list) })
  )
)
