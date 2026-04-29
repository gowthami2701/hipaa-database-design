-- ============================================================
-- HIPAA-Compliant Healthcare Database Design
-- Portfolio Project 3 | Health Information Technology
-- Author: Gowthami Vasamsetti
-- ============================================================
-- This schema demonstrates enterprise-grade healthcare database
-- design with PHI protection, audit logging, access controls,
-- and HIPAA/HITECH compliance best practices.
-- ============================================================

-- ── SCHEMA SETUP ──────────────────────────────────────────────────────────────

CREATE SCHEMA IF NOT EXISTS clinic_db;
CREATE SCHEMA IF NOT EXISTS audit_log;
CREATE SCHEMA IF NOT EXISTS phi_vault;   -- Encrypted PHI separated from clinical data
SET search_path TO clinic_db;

-- ── ROLE-BASED ACCESS CONTROL ─────────────────────────────────────────────────
-- HIPAA Minimum Necessary Rule: each role sees only what they need

-- DO $$ BEGIN
--   CREATE ROLE clinic_admin;       -- Full access
--   CREATE ROLE physician;          -- Read/write clinical data, read PHI
--   CREATE ROLE nurse_practitioner; -- Read/write clinical data, limited PHI
--   CREATE ROLE billing_staff;      -- Billing data only, NO clinical notes
--   CREATE ROLE readonly_analyst;   -- Aggregated/de-identified data only
--   CREATE ROLE auditor;            -- Audit logs only
-- EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── PHI VAULT (Separated PII/PHI) ────────────────────────────────────────────

CREATE TABLE phi_vault.patient_identity (
    patient_uid         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Encrypted PHI fields (would use pgcrypto in production)
    first_name_enc      TEXT NOT NULL,           -- pgp_sym_encrypt(first_name, key)
    last_name_enc       TEXT NOT NULL,
    dob_enc             TEXT NOT NULL,           -- Encrypted date of birth
    ssn_hash            TEXT,                    -- bcrypt hash, never stored plaintext
    mrn                 VARCHAR(20) UNIQUE NOT NULL,
    created_at          TIMESTAMP DEFAULT NOW(),
    created_by          TEXT DEFAULT CURRENT_USER,
    last_accessed       TIMESTAMP,
    access_count        INTEGER DEFAULT 0
);

-- ── CORE CLINICAL TABLES ──────────────────────────────────────────────────────

-- Patients (de-identified operational data - separated from PHI)
CREATE TABLE patients (
    patient_uid         UUID PRIMARY KEY REFERENCES phi_vault.patient_identity(patient_uid),
    age_group           VARCHAR(10),             -- Bucketed, not exact DOB
    gender              CHAR(1),
    race_ethnicity      VARCHAR(50),
    zip_code_3digit     CHAR(3),                 -- Only first 3 digits per HIPAA Safe Harbor
    insurance_type      VARCHAR(50),
    primary_care_provider_id INTEGER,
    consent_signed      BOOLEAN DEFAULT FALSE,
    consent_date        DATE,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP DEFAULT NOW()
);

-- Providers
CREATE TABLE providers (
    provider_id         SERIAL PRIMARY KEY,
    npi                 VARCHAR(10) UNIQUE NOT NULL,
    full_name           VARCHAR(100) NOT NULL,
    specialty           VARCHAR(100),
    department          VARCHAR(100),
    credential          VARCHAR(20),             -- MD, NP, PA, etc.
    is_active           BOOLEAN DEFAULT TRUE,
    hipaa_training_date DATE,
    system_access_level VARCHAR(20) DEFAULT 'standard'
);

-- Appointments
CREATE TABLE appointments (
    appointment_id      SERIAL PRIMARY KEY,
    patient_uid         UUID NOT NULL REFERENCES patients(patient_uid),
    provider_id         INTEGER NOT NULL REFERENCES providers(provider_id),
    scheduled_date      DATE NOT NULL,
    scheduled_time      TIME,
    appointment_type    VARCHAR(50),
    status              VARCHAR(20) DEFAULT 'Scheduled',
    chief_complaint     TEXT,
    duration_minutes    INTEGER DEFAULT 30,
    location            VARCHAR(100),
    created_at          TIMESTAMP DEFAULT NOW(),
    CONSTRAINT valid_status CHECK (status IN ('Scheduled','Checked-In','In-Progress','Completed','No-Show','Cancelled'))
);

-- Encounters (Clinical Visit Records)
CREATE TABLE encounters (
    encounter_id        SERIAL PRIMARY KEY,
    appointment_id      INTEGER REFERENCES appointments(appointment_id),
    patient_uid         UUID NOT NULL REFERENCES patients(patient_uid),
    provider_id         INTEGER NOT NULL REFERENCES providers(provider_id),
    encounter_date      DATE NOT NULL,
    encounter_type      VARCHAR(50),
    visit_reason        TEXT,
    -- Clinical documentation
    subjective_note     TEXT,                    -- SOAP note - S
    objective_note      TEXT,                    -- SOAP note - O
    assessment_note     TEXT,                    -- SOAP note - A
    plan_note           TEXT,                    -- SOAP note - P
    -- Status flags
    is_signed           BOOLEAN DEFAULT FALSE,
    signed_at           TIMESTAMP,
    is_locked           BOOLEAN DEFAULT FALSE,
    created_at          TIMESTAMP DEFAULT NOW(),
    last_modified       TIMESTAMP DEFAULT NOW()
);

-- Diagnoses (ICD-10-CM)
CREATE TABLE diagnoses (
    diagnosis_id        SERIAL PRIMARY KEY,
    encounter_id        INTEGER NOT NULL REFERENCES encounters(encounter_id),
    patient_uid         UUID NOT NULL REFERENCES patients(patient_uid),
    icd10_code          VARCHAR(10) NOT NULL,
    icd10_description   TEXT NOT NULL,
    diagnosis_type      VARCHAR(20),             -- Primary, Secondary, Admitting
    onset_date          DATE,
    resolved_date       DATE,
    is_chronic          BOOLEAN DEFAULT FALSE,
    severity            VARCHAR(20),
    entered_by          INTEGER REFERENCES providers(provider_id),
    created_at          TIMESTAMP DEFAULT NOW()
);

-- Procedures (CPT/HCPCS)
CREATE TABLE procedures (
    procedure_id        SERIAL PRIMARY KEY,
    encounter_id        INTEGER NOT NULL REFERENCES encounters(encounter_id),
    patient_uid         UUID NOT NULL REFERENCES patients(patient_uid),
    provider_id         INTEGER NOT NULL REFERENCES providers(provider_id),
    cpt_code            VARCHAR(10) NOT NULL,
    cpt_description     TEXT NOT NULL,
    procedure_date      DATE NOT NULL,
    modifier            VARCHAR(10),
    quantity            INTEGER DEFAULT 1,
    status              VARCHAR(20) DEFAULT 'Performed',
    notes               TEXT,
    created_at          TIMESTAMP DEFAULT NOW()
);

-- Medications
CREATE TABLE medications (
    medication_id       SERIAL PRIMARY KEY,
    patient_uid         UUID NOT NULL REFERENCES patients(patient_uid),
    encounter_id        INTEGER REFERENCES encounters(encounter_id),
    provider_id         INTEGER REFERENCES providers(provider_id),
    drug_name           VARCHAR(200) NOT NULL,
    ndc_code            VARCHAR(15),             -- National Drug Code
    rxnorm_code         VARCHAR(20),
    dose                VARCHAR(50),
    route               VARCHAR(50),
    frequency           VARCHAR(50),
    start_date          DATE,
    end_date            DATE,
    is_active           BOOLEAN DEFAULT TRUE,
    is_controlled       BOOLEAN DEFAULT FALSE,
    created_at          TIMESTAMP DEFAULT NOW()
);

-- Lab Results
CREATE TABLE lab_results (
    result_id           SERIAL PRIMARY KEY,
    patient_uid         UUID NOT NULL REFERENCES patients(patient_uid),
    encounter_id        INTEGER REFERENCES encounters(encounter_id),
    loinc_code          VARCHAR(20),             -- LOINC standard coding
    test_name           VARCHAR(200) NOT NULL,
    result_value        VARCHAR(100),
    result_unit         VARCHAR(50),
    reference_low       DECIMAL(10,3),
    reference_high      DECIMAL(10,3),
    is_abnormal         BOOLEAN,
    critical_flag       BOOLEAN DEFAULT FALSE,
    collected_date      TIMESTAMP,
    resulted_date       TIMESTAMP,
    ordering_provider   INTEGER REFERENCES providers(provider_id),
    performing_lab      VARCHAR(100),
    created_at          TIMESTAMP DEFAULT NOW()
);

-- ── BILLING TABLES ────────────────────────────────────────────────────────────

CREATE TABLE claims (
    claim_id            SERIAL PRIMARY KEY,
    encounter_id        INTEGER NOT NULL REFERENCES encounters(encounter_id),
    patient_uid         UUID NOT NULL REFERENCES patients(patient_uid),
    claim_number        VARCHAR(20) UNIQUE NOT NULL,
    payer_id            INTEGER,
    payer_name          VARCHAR(100),
    total_charges       DECIMAL(10,2),
    total_payments      DECIMAL(10,2),
    total_adjustments   DECIMAL(10,2),
    balance             DECIMAL(10,2) GENERATED ALWAYS AS (total_charges - total_payments - total_adjustments) STORED,
    claim_status        VARCHAR(30) DEFAULT 'Draft',
    submit_date         DATE,
    payment_date        DATE,
    denial_code         VARCHAR(10),
    denial_reason       TEXT,
    created_at          TIMESTAMP DEFAULT NOW()
);

-- ── AUDIT LOGGING (HIPAA §164.312(b)) ────────────────────────────────────────
-- Every access to PHI must be logged

CREATE TABLE audit_log.access_log (
    log_id              BIGSERIAL PRIMARY KEY,
    event_timestamp     TIMESTAMP NOT NULL DEFAULT NOW(),
    db_user             TEXT NOT NULL DEFAULT CURRENT_USER,
    application_user    TEXT,
    action_type         VARCHAR(20) NOT NULL,    -- SELECT, INSERT, UPDATE, DELETE
    table_name          TEXT NOT NULL,
    record_id           TEXT,
    patient_uid         UUID,
    -- What changed (for UPDATE/DELETE)
    old_values          JSONB,
    new_values          JSONB,
    ip_address          INET,
    session_id          TEXT,
    -- Compliance fields
    access_reason       TEXT,                    -- Required for PHI access
    authorized          BOOLEAN DEFAULT TRUE
);

-- Separate security event log
CREATE TABLE audit_log.security_events (
    event_id            BIGSERIAL PRIMARY KEY,
    event_timestamp     TIMESTAMP NOT NULL DEFAULT NOW(),
    event_type          VARCHAR(50),             -- LOGIN, LOGOUT, FAILED_LOGIN, EXPORT, etc.
    db_user             TEXT,
    ip_address          INET,
    details             JSONB,
    severity            VARCHAR(10) DEFAULT 'INFO'  -- INFO, WARN, CRITICAL
);

-- ── AUDIT TRIGGER FUNCTION ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION audit_log.log_phi_access()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log.access_log 
            (action_type, table_name, record_id, old_values)
        VALUES 
            (TG_OP, TG_TABLE_NAME, OLD.patient_uid::TEXT, row_to_json(OLD)::JSONB);
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log.access_log 
            (action_type, table_name, record_id, old_values, new_values)
        VALUES 
            (TG_OP, TG_TABLE_NAME, NEW.patient_uid::TEXT, 
             row_to_json(OLD)::JSONB, row_to_json(NEW)::JSONB);
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log.access_log 
            (action_type, table_name, record_id, new_values)
        VALUES 
            (TG_OP, TG_TABLE_NAME, NEW.patient_uid::TEXT, row_to_json(NEW)::JSONB);
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Apply audit triggers to all PHI-containing tables
CREATE TRIGGER audit_patients
    AFTER INSERT OR UPDATE OR DELETE ON patients
    FOR EACH ROW EXECUTE FUNCTION audit_log.log_phi_access();

CREATE TRIGGER audit_encounters
    AFTER INSERT OR UPDATE OR DELETE ON encounters
    FOR EACH ROW EXECUTE FUNCTION audit_log.log_phi_access();

CREATE TRIGGER audit_diagnoses
    AFTER INSERT OR UPDATE OR DELETE ON diagnoses
    FOR EACH ROW EXECUTE FUNCTION audit_log.log_phi_access();

CREATE TRIGGER audit_medications
    AFTER INSERT OR UPDATE OR DELETE ON medications
    FOR EACH ROW EXECUTE FUNCTION audit_log.log_phi_access();

-- ── DE-IDENTIFICATION VIEW (Safe Harbor Method) ───────────────────────────────
-- HIPAA §164.514(b) - Safe Harbor: remove 18 identifiers

CREATE VIEW deidentified_encounters AS
SELECT
    e.encounter_id,
    -- Age generalized to decade
    CASE 
        WHEN p.age_group = '<45'  THEN 'Under 45'
        WHEN p.age_group = '45-65' THEN '45-65'
        WHEN p.age_group = '65-75' THEN '65-75'
        ELSE 'Over 75'
    END                         AS age_group,
    p.gender,
    p.race_ethnicity,
    -- Geography: 3-digit zip only
    p.zip_code_3digit           AS zip_region,
    p.insurance_type,
    e.encounter_type,
    e.encounter_date,
    -- No provider name - just specialty
    prov.specialty              AS provider_specialty,
    d.icd10_code,
    d.icd10_description,
    d.is_chronic
FROM encounters e
JOIN patients p          ON e.patient_uid = p.patient_uid
JOIN providers prov      ON e.provider_id = prov.provider_id
LEFT JOIN diagnoses d    ON e.encounter_id = d.encounter_id AND d.diagnosis_type = 'Primary'
-- Exclude records where dates fall outside safe ranges
WHERE e.encounter_date IS NOT NULL;

-- Grant read-only access to analysts on de-identified view only
-- GRANT SELECT ON deidentified_encounters TO readonly_analyst;

-- ── COMPLIANCE REPORT QUERIES ─────────────────────────────────────────────────

-- Who accessed PHI in the last 24 hours?
SELECT 
    db_user, action_type, table_name, COUNT(*) AS access_count,
    MIN(event_timestamp) AS first_access,
    MAX(event_timestamp) AS last_access
FROM audit_log.access_log
WHERE event_timestamp >= NOW() - INTERVAL '24 hours'
GROUP BY db_user, action_type, table_name
ORDER BY access_count DESC;

-- Unusual access patterns (>100 records in 1 hour - potential breach indicator)
SELECT
    db_user, DATE_TRUNC('hour', event_timestamp) AS hour_bucket,
    COUNT(*) AS records_accessed
FROM audit_log.access_log
WHERE action_type = 'SELECT'
GROUP BY db_user, hour_bucket
HAVING COUNT(*) > 100
ORDER BY records_accessed DESC;

-- Patients with most diagnoses (population health insight - using de-identified view)
SELECT 
    age_group, gender, race_ethnicity, icd10_code, icd10_description,
    COUNT(*) AS patient_count
FROM deidentified_encounters
WHERE is_chronic = TRUE
GROUP BY age_group, gender, race_ethnicity, icd10_code, icd10_description
HAVING COUNT(*) >= 5    -- Cell suppression: hide counts < 5 per HIPAA
ORDER BY patient_count DESC;
