;; Music Royalty Distribution System
;; Automates royalty tracking, calculation, and distribution for artists and rights holders

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u100))
(define-constant err-not-found (err u101))
(define-constant err-invalid-input (err u102))
(define-constant err-insufficient-balance (err u103))
(define-constant err-already-exists (err u104))
(define-constant err-invalid-split (err u105))
(define-constant err-payout-failed (err u106))

;; Data variables
(define-data-var track-counter uint u0)
(define-data-var usage-event-counter uint u0)
(define-data-var payout-cycle-counter uint u0)
(define-data-var dispute-counter uint u0)

;; Platform and territory constants
(define-constant platform-spotify "SPOTIFY")
(define-constant platform-apple "APPLE_MUSIC")
(define-constant platform-youtube "YOUTUBE")
(define-constant platform-radio "RADIO")

;; Data maps
(define-map tracks
  { track-id: uint }
  {
    isrc: (string-ascii 20),
    title: (string-ascii 100),
    artist: (string-ascii 100),
    label: principal,
    created-at: uint,
    active: bool,
    total-plays: uint,
    total-royalties: uint
  }
)

(define-map track-rights-holders
  { track-id: uint, holder-id: uint }
  {
    holder: principal,
    role: (string-ascii 20),
    split-percentage: uint,
    territory: (string-ascii 10),
    active: bool
  }
)

(define-map usage-events
  { event-id: uint }
  {
    track-id: uint,
    platform: (string-ascii 20),
    territory: (string-ascii 10),
    play-count: uint,
    revenue-generated: uint,
    timestamp: uint,
    event-hash: (buff 32),
    verified: bool,
    reported-by: principal
  }
)

(define-map royalty-rates
  { platform: (string-ascii 20), territory: (string-ascii 10) }
  {
    rate-per-stream: uint,
    minimum-payout: uint,
    currency: (string-ascii 10),
    updated-at: uint
  }
)

(define-map royalty-accruals
  { track-id: uint, holder: principal }
  {
    pending-amount: uint,
    total-earned: uint,
    last-payout-cycle: uint,
    payout-threshold: uint
  }
)

(define-map payout-cycles
  { cycle-id: uint }
  {
    start-date: uint,
    end-date: uint,
    total-distributed: uint,
    tracks-processed: uint,
    status: (string-ascii 20),
    created-by: principal
  }
)

(define-map payouts
  { payout-id: uint }
  {
    cycle-id: uint,
    track-id: uint,
    recipient: principal,
    amount: uint,
    transaction-hash: (optional (buff 32)),
    status: (string-ascii 20),
    processed-at: uint
  }
)

(define-map disputes
  { dispute-id: uint }
  {
    track-id: uint,
    disputer: principal,
    dispute-type: (string-ascii 30),
    description-hash: (buff 32),
    evidence-hash: (optional (buff 32)),
    status: (string-ascii 20),
    created-at: uint,
    resolved-at: (optional uint),
    resolution: (optional (string-ascii 200))
  }
)

(define-map user-roles
  { user: principal }
  {
    role: (string-ascii 20),
    permissions: (list 10 (string-ascii 20)),
    approved-by: principal,
    active: bool
  }
)

;; Authorization functions
(define-private (is-contract-owner)
  (is-eq tx-sender contract-owner)
)

(define-private (is-authorized-reporter)
  (or (is-contract-owner)
      (match (map-get? user-roles { user: tx-sender })
        role (and (get active role) (is-eq (get role role) "REPORTER"))
        false
      )
  )
)

(define-private (is-track-owner (track-id uint))
  (match (map-get? tracks { track-id: track-id })
    track (is-eq tx-sender (get label track))
    false
  )
)

;; Track management functions
(define-public (register-track
  (isrc (string-ascii 20))
  (title (string-ascii 100))
  (artist (string-ascii 100))
)
  (let 
    (
      (track-id (+ (var-get track-counter) u1))
      (current-time u1)
    )
    (begin
      (map-set tracks
        { track-id: track-id }
        {
          isrc: isrc,
          title: title,
          artist: artist,
          label: tx-sender,
          created-at: current-time,
          active: true,
          total-plays: u0,
          total-royalties: u0
        }
      )
      
      (var-set track-counter track-id)
      (ok track-id)
    )
  )
)

(define-public (add-rights-holder
  (track-id uint)
  (holder principal)
  (role (string-ascii 20))
  (split-percentage uint)
  (territory (string-ascii 10))
)
  (begin
    (asserts! (is-track-owner track-id) err-unauthorized)
    (asserts! (<= split-percentage u10000) err-invalid-split)
    (asserts! (is-some (map-get? tracks { track-id: track-id })) err-not-found)
    
    (let ((holder-id (+ u1 (get-next-holder-id track-id))))
      (map-set track-rights-holders
        { track-id: track-id, holder-id: holder-id }
        {
          holder: holder,
          role: role,
          split-percentage: split-percentage,
          territory: territory,
          active: true
        }
      )
      (ok holder-id)
    )
  )
)

;; Usage tracking functions
(define-public (report-usage
  (track-id uint)
  (platform (string-ascii 20))
  (territory (string-ascii 10))
  (play-count uint)
  (revenue-generated uint)
  (event-hash (buff 32))
)
  (begin
    (asserts! (is-authorized-reporter) err-unauthorized)
    (asserts! (is-some (map-get? tracks { track-id: track-id })) err-not-found)
    (asserts! (> play-count u0) err-invalid-input)
    
    (let 
      (
        (event-id (+ (var-get usage-event-counter) u1))
        (current-time u1)
      )
      (begin
        (map-set usage-events
          { event-id: event-id }
          {
            track-id: track-id,
            platform: platform,
            territory: territory,
            play-count: play-count,
            revenue-generated: revenue-generated,
            timestamp: current-time,
            event-hash: event-hash,
            verified: false,
            reported-by: tx-sender
          }
        )
        
        ;; Update track totals
        (match (map-get? tracks { track-id: track-id })
          track
          (map-set tracks
            { track-id: track-id }
            (merge track {
              total-plays: (+ (get total-plays track) play-count),
              total-royalties: (+ (get total-royalties track) revenue-generated)
            })
          )
          false
        )
        
        (var-set usage-event-counter event-id)
        (ok event-id)
      )
    )
  )
)

(define-public (verify-usage-event (event-id uint))
  (begin
    (asserts! (is-contract-owner) err-unauthorized)
    
    (match (map-get? usage-events { event-id: event-id })
      event
      (begin
        (map-set usage-events
          { event-id: event-id }
          (merge event { verified: true })
        )
        (ok true)
      )
      err-not-found
    )
  )
)

;; Royalty calculation and accrual
(define-public (calculate-royalties (track-id uint) (event-id uint))
  (begin
    (asserts! (is-authorized-reporter) err-unauthorized)
    
    (match (map-get? usage-events { event-id: event-id })
      event
      (begin
        (asserts! (get verified event) err-unauthorized)
        (asserts! (is-eq (get track-id event) track-id) err-invalid-input)
        
        (let ((revenue (get revenue-generated event)))
          (unwrap! (distribute-to-rights-holders track-id revenue) err-invalid-input)
          (ok revenue)
        )
      )
      err-not-found
    )
  )
)

(define-private (distribute-to-rights-holders (track-id uint) (total-revenue uint))
  ;; Simplified distribution - in production would iterate through all rights holders
  (let ((holder-1-share (/ (* total-revenue u5000) u10000)))  ;; 50% split example
    (ok total-revenue)
  )
)

;; Payout cycle management
(define-public (create-payout-cycle
  (start-date uint)
  (end-date uint)
)
  (begin
    (asserts! (is-contract-owner) err-unauthorized)
    
    (let ((cycle-id (+ (var-get payout-cycle-counter) u1)))
      (map-set payout-cycles
        { cycle-id: cycle-id }
        {
          start-date: start-date,
          end-date: end-date,
          total-distributed: u0,
          tracks-processed: u0,
          status: "ACTIVE",
          created-by: tx-sender
        }
      )
      
      (var-set payout-cycle-counter cycle-id)
      (ok cycle-id)
    )
  )
)

(define-public (process-payout
  (cycle-id uint)
  (track-id uint)
  (recipient principal)
  (amount uint)
)
  (begin
    (asserts! (is-contract-owner) err-unauthorized)
    (asserts! (is-some (map-get? payout-cycles { cycle-id: cycle-id })) err-not-found)
    (asserts! (> amount u0) err-invalid-input)
    
    ;; In a real implementation, this would transfer STX or other tokens
    ;; For this MVP, we just record the payout intent
    (let ((payout-id (+ u1 (get-next-payout-id))))
      (map-set payouts
        { payout-id: payout-id }
        {
          cycle-id: cycle-id,
          track-id: track-id,
          recipient: recipient,
          amount: amount,
          transaction-hash: none,
          status: "PENDING",
          processed-at: u1
        }
      )
      (ok payout-id)
    )
  )
)

;; Dispute management
(define-public (submit-dispute
  (track-id uint)
  (dispute-type (string-ascii 30))
  (description-hash (buff 32))
)
  (begin
    (asserts! (is-some (map-get? tracks { track-id: track-id })) err-not-found)
    
    (let 
      (
        (dispute-id (+ (var-get dispute-counter) u1))
        (current-time u1)
      )
      (begin
        (map-set disputes
          { dispute-id: dispute-id }
          {
            track-id: track-id,
            disputer: tx-sender,
            dispute-type: dispute-type,
            description-hash: description-hash,
            evidence-hash: none,
            status: "OPEN",
            created-at: current-time,
            resolved-at: none,
            resolution: none
          }
        )
        
        (var-set dispute-counter dispute-id)
        (ok dispute-id)
      )
    )
  )
)

(define-public (resolve-dispute
  (dispute-id uint)
  (resolution (string-ascii 200))
)
  (begin
    (asserts! (is-contract-owner) err-unauthorized)
    
    (match (map-get? disputes { dispute-id: dispute-id })
      dispute
      (begin
        (map-set disputes
          { dispute-id: dispute-id }
          (merge dispute {
            status: "RESOLVED",
            resolved-at: (some u1),
            resolution: (some resolution)
          })
        )
        (ok true)
      )
      err-not-found
    )
  )
)

;; Helper functions
(define-private (get-next-holder-id (track-id uint))
  ;; Simplified - in production would track per track
  u0
)

(define-private (get-next-payout-id)
  ;; Simplified - in production would track globally
  u0
)

;; Read-only functions
(define-read-only (get-track (track-id uint))
  (map-get? tracks { track-id: track-id })
)

(define-read-only (get-usage-event (event-id uint))
  (map-get? usage-events { event-id: event-id })
)

(define-read-only (get-rights-holder (track-id uint) (holder-id uint))
  (map-get? track-rights-holders { track-id: track-id, holder-id: holder-id })
)

(define-read-only (get-royalty-accrual (track-id uint) (holder principal))
  (map-get? royalty-accruals { track-id: track-id, holder: holder })
)

(define-read-only (get-payout-cycle (cycle-id uint))
  (map-get? payout-cycles { cycle-id: cycle-id })
)

(define-read-only (get-payout (payout-id uint))
  (map-get? payouts { payout-id: payout-id })
)

(define-read-only (get-dispute (dispute-id uint))
  (map-get? disputes { dispute-id: dispute-id })
)

(define-read-only (get-track-counter)
  (var-get track-counter)
)

(define-read-only (get-usage-event-counter)
  (var-get usage-event-counter)
)

(define-read-only (get-payout-cycle-counter)
  (var-get payout-cycle-counter)
)

(define-read-only (get-user-role (user principal))
  (map-get? user-roles { user: user })
)

