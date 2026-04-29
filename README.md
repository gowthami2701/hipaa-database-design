# 🔐 HIPAA-Compliant Healthcare Database Design
### Healthcare Data Analyst Portfolio Project | Health Informatics

![Project Status](https://img.shields.io/badge/Status-Complete-brightgreen)
![Tools](https://img.shields.io/badge/Tools-PostgreSQL%20%7C%20SQL-blue)
![Compliance](https://img.shields.io/badge/Compliance-HIPAA%20%7C%20HITECH-red)

---

## 📌 Business Problem

A multi-specialty clinic is transitioning from paper records to a digital EHR system. They need a **production-grade database** that:
- Protects PHI in compliance with HIPAA Privacy & Security Rules (45 CFR Parts 160 and 164)
- Implements role-based access control (RBAC) per the Minimum Necessary Rule
- Maintains complete audit trails for all PHI access (required by §164.312(b))
- Supports ICD-10-CM diagnosis coding and CPT procedure coding
- Enables de-identified analytics without exposing patient identifiers

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────┐
│              APPLICATION LAYER               │
│         (EHR UI / API / Reporting)           │
└────────────────────┬────────────────────────┘
                     │
┌────────────────────▼────────────────────────┐
│              ROLE-BASED ACCESS               │
│  clinic_admin | physician | billing_staff    │
│  nurse_practitioner | readonly_analyst       │
└────────────────────┬────────────────────────┘
                     │
┌────────────────────▼────────────────────────┐
│           POSTGRESQL DATABASE                │
│  ┌─────────────┐  ┌──────────────────────┐  │
│  │  phi_vault  │  │     clinic_db        │  │
│  │  (encrypted │  │  (clinical + billing │  │
│  │   PII/PHI)  │  │   de-identified)     │  │
│  └─────────────┘  └──────────────────────┘  │
│  ┌──────────────────────────────────────┐   │
│  │         audit_log schema             │   │
│  │  (every PHI access logged forever)   │   │
│  └──────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

---

## 🛡️ HIPAA Compliance Features Implemented

| HIPAA Rule | Implementation |
|-----------|---------------|
| Privacy Rule - Minimum Necessary | Role-based views; billing staff cannot see clinical notes |
| Security Rule - Access Control §164.312(a)(1) | PostgreSQL RBAC with least-privilege roles |
| Security Rule - Audit Controls §164.312(b) | Automatic trigger-based audit logging on all PHI tables |
| Security Rule - Encryption §164.312(a)(2)(iv) | PHI vault with pgcrypto encryption fields |
| Privacy Rule - De-identification §164.514(b) | Safe Harbor view removing all 18 identifiers |
| Breach Notification Rule | Security events log for anomaly detection |

---

## 📁 Files

- `hipaa_database_schema.sql` — Complete database schema with all tables, triggers, views, and compliance queries
- `README.md` — This file

---

## 🚀 How to Run

```bash
# Requires PostgreSQL 14+
psql -U postgres -c "CREATE DATABASE clinic_db;"
psql -U postgres -d clinic_db -f hipaa_database_schema.sql

# Verify audit logging
psql -U postgres -d clinic_db -c "SELECT * FROM audit_log.access_log LIMIT 10;"
```

---

## 💼 Skills Demonstrated
- Enterprise healthcare database architecture
- HIPAA Privacy & Security Rule compliance
- PostgreSQL advanced features (triggers, schemas, views, stored procedures)
- PHI encryption and de-identification (Safe Harbor method)
- Role-based access control design
- ICD-10-CM and CPT coding integration
- Audit trail implementation
