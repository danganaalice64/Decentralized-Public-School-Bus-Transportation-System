;; Driver Qualification Verification Contract
;; Validates bus driver licenses, training, and background checks

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-DRIVER-NOT-FOUND (err u301))
(define-constant ERR-INVALID-INPUT (err u302))
(define-constant ERR-LICENSE-EXPIRED (err u303))
(define-constant ERR-TRAINING-INCOMPLETE (err u304))

;; Data Variables
(define-data-var verification-active bool true)
(define-data-var next-driver-id uint u1)

;; Data Maps
(define-map driver-profiles
  { driver-id: uint }
  {
    name: (string-ascii 50),
    license-number: (string-ascii 20),
    license-expiry: uint,
    hire-date: uint,
    phone: (string-ascii 15),
    emergency-contact: (string-ascii 15),
    status: (string-ascii 20),
    created-at: uint
  }
)

(define-map driver-qualifications
  { driver-id: uint }
  {
    cdl-valid: bool,
    cdl-expiry: uint,
    background-check: bool,
    background-check-date: uint,
    medical-clearance: bool,
    medical-expiry: uint,
    drug-test: bool,
    drug-test-date: uint
  }
)

(define-map training-records
  { driver-id: uint, training-type: (string-ascii 30) }
  {
    completed: bool,
    completion-date: uint,
    expiry-date: uint,
    instructor: (string-ascii 50),
    score: uint,
    notes: (string-ascii 100)
  }
)

(define-map violation-records
  { driver-id: uint, violation-id: uint }
  {
    violation-type: (string-ascii 50),
    date: uint,
    description: (string-ascii 200),
    severity: uint,
    resolved: bool,
    resolution-date: (optional uint)
  }
)

;; Read-only functions
(define-read-only (get-driver-profile (driver-id uint))
  (map-get? driver-profiles { driver-id: driver-id })
)

(define-read-only (get-driver-qualifications (driver-id uint))
  (map-get? driver-qualifications { driver-id: driver-id })
)

(define-read-only (get-training-record (driver-id uint) (training-type (string-ascii 30)))
  (map-get? training-records { driver-id: driver-id, training-type: training-type })
)

(define-read-only (get-violation-record (driver-id uint) (violation-id uint))
  (map-get? violation-records { driver-id: driver-id, violation-id: violation-id })
)

(define-read-only (is-driver-qualified (driver-id uint))
  (match (get-driver-qualifications driver-id)
    qualifications (and
      (get cdl-valid qualifications)
      (> (get cdl-expiry qualifications) block-height)
      (get background-check qualifications)
      (get medical-clearance qualifications)
      (> (get medical-expiry qualifications) block-height)
      (get drug-test qualifications)
    )
    false
  )
)

(define-read-only (get-next-driver-id)
  (var-get next-driver-id)
)

;; Public functions
(define-public (register-driver (name (string-ascii 50)) (license-number (string-ascii 20)) (license-expiry uint) (phone (string-ascii 15)) (emergency-contact (string-ascii 15)))
  (let ((driver-id (var-get next-driver-id)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (var-get verification-active) ERR-NOT-AUTHORIZED)
    (asserts! (> license-expiry block-height) ERR-LICENSE-EXPIRED)

    (map-set driver-profiles
      { driver-id: driver-id }
      {
        name: name,
        license-number: license-number,
        license-expiry: license-expiry,
        hire-date: block-height,
        phone: phone,
        emergency-contact: emergency-contact,
        status: "pending",
        created-at: block-height
      }
    )

    (var-set next-driver-id (+ driver-id u1))
    (ok driver-id)
  )
)

(define-public (update-qualifications (driver-id uint) (cdl-valid bool) (cdl-expiry uint) (background-check bool) (background-check-date uint) (medical-clearance bool) (medical-expiry uint) (drug-test bool) (drug-test-date uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (get-driver-profile driver-id)) ERR-DRIVER-NOT-FOUND)
    (asserts! (var-get verification-active) ERR-NOT-AUTHORIZED)

    (map-set driver-qualifications
      { driver-id: driver-id }
      {
        cdl-valid: cdl-valid,
        cdl-expiry: cdl-expiry,
        background-check: background-check,
        background-check-date: background-check-date,
        medical-clearance: medical-clearance,
        medical-expiry: medical-expiry,
        drug-test: drug-test,
        drug-test-date: drug-test-date
      }
    )
    (ok true)
  )
)

(define-public (record-training (driver-id uint) (training-type (string-ascii 30)) (completion-date uint) (expiry-date uint) (instructor (string-ascii 50)) (score uint) (notes (string-ascii 100)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (get-driver-profile driver-id)) ERR-DRIVER-NOT-FOUND)
    (asserts! (var-get verification-active) ERR-NOT-AUTHORIZED)
    (asserts! (<= score u100) ERR-INVALID-INPUT)
    (asserts! (>= score u70) ERR-INVALID-INPUT) ;; Minimum passing score

    (map-set training-records
      { driver-id: driver-id, training-type: training-type }
      {
        completed: true,
        completion-date: completion-date,
        expiry-date: expiry-date,
        instructor: instructor,
        score: score,
        notes: notes
      }
    )
    (ok true)
  )
)

(define-public (record-violation (driver-id uint) (violation-id uint) (violation-type (string-ascii 50)) (description (string-ascii 200)) (severity uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (get-driver-profile driver-id)) ERR-DRIVER-NOT-FOUND)
    (asserts! (var-get verification-active) ERR-NOT-AUTHORIZED)
    (asserts! (<= severity u5) ERR-INVALID-INPUT)
    (asserts! (> severity u0) ERR-INVALID-INPUT)

    (map-set violation-records
      { driver-id: driver-id, violation-id: violation-id }
      {
        violation-type: violation-type,
        date: block-height,
        description: description,
        severity: severity,
        resolved: false,
        resolution-date: none
      }
    )
    (ok true)
  )
)

(define-public (resolve-violation (driver-id uint) (violation-id uint))
  (let ((violation (unwrap! (get-violation-record driver-id violation-id) ERR-DRIVER-NOT-FOUND)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (var-get verification-active) ERR-NOT-AUTHORIZED)

    (map-set violation-records
      { driver-id: driver-id, violation-id: violation-id }
      (merge violation {
        resolved: true,
        resolution-date: (some block-height)
      })
    )
    (ok true)
  )
)

(define-public (update-driver-status (driver-id uint) (new-status (string-ascii 20)))
  (let ((profile (unwrap! (get-driver-profile driver-id) ERR-DRIVER-NOT-FOUND)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (var-get verification-active) ERR-NOT-AUTHORIZED)

    (map-set driver-profiles
      { driver-id: driver-id }
      (merge profile { status: new-status })
    )
    (ok true)
  )
)

(define-public (toggle-verification-system)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set verification-active (not (var-get verification-active)))
    (ok (var-get verification-active))
  )
)
