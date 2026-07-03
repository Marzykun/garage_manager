CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- CUSTOMERS
CREATE TABLE customers (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  phone         TEXT UNIQUE NOT NULL,
  language_pref TEXT DEFAULT 'EN',
  created_at    TIMESTAMPTZ DEFAULT now()
);

-- VEHICLES (updated with km_run, tyre_size, year)
CREATE TABLE vehicles (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id    UUID REFERENCES customers(id) ON DELETE CASCADE,
  vehicle_number TEXT UNIQUE NOT NULL,
  vehicle_type   TEXT,
  brand          TEXT,
  model          TEXT,
  year           INTEGER,
  km_run         INTEGER DEFAULT 0,
  tyre_size      TEXT,
  created_at     TIMESTAMPTZ DEFAULT now()
);

-- SERVICE TYPE ENUM
CREATE TYPE service_type AS ENUM (
  'wheel_alignment',
  'wheel_balancing',
  'tyre_change',
  'water_wash',
  'full_service',
  'car_wash',
  'other'
);

CREATE TYPE job_status AS ENUM ('pending', 'in_progress', 'completed');
CREATE TYPE job_source AS ENUM ('walkin', 'whatsapp');

-- JOB CARDS (updated with service_type, date, time)
CREATE TABLE job_cards (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id     UUID REFERENCES customers(id) ON DELETE RESTRICT,
  vehicle_id      UUID REFERENCES vehicles(id) ON DELETE RESTRICT,
  service_type    service_type NOT NULL,
  status          job_status DEFAULT 'pending',
  source          job_source DEFAULT 'walkin',
  service_date    DATE,
  service_time    TIME,
  notes           TEXT,
  ready_for_delivery BOOLEAN DEFAULT FALSE,
  created_at      TIMESTAMPTZ DEFAULT now(),
  completed_at    TIMESTAMPTZ,
  reminder_date   TIMESTAMPTZ
);

-- JOB ISSUES
CREATE TYPE issue_source AS ENUM ('mechanic', 'customer');
CREATE TABLE job_issues (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_card_id UUID REFERENCES job_cards(id) ON DELETE CASCADE,
  description TEXT NOT NULL,
  source      issue_source DEFAULT 'mechanic',
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- WHEEL BALANCING
CREATE TABLE wheel_balancing (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_card_id UUID REFERENCES job_cards(id) ON DELETE CASCADE,
  fl_weight   NUMERIC(6,2),
  fr_weight   NUMERIC(6,2),
  rl_weight   NUMERIC(6,2),
  rr_weight   NUMERIC(6,2),
  remarks     TEXT,
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- WHEEL ALIGNMENT
CREATE TABLE wheel_alignment (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_card_id      UUID REFERENCES job_cards(id) ON DELETE CASCADE,
  alignment_report TEXT,
  remarks          TEXT,
  created_at       TIMESTAMPTZ DEFAULT now()
);

-- INVENTORY
CREATE TYPE inventory_category AS ENUM (
  'tyre', 'wheel_weight', 'foam', 'lubricant', 'other'
);
CREATE TABLE inventory (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  category    inventory_category NOT NULL,
  quantity    INTEGER DEFAULT 0,
  unit        TEXT DEFAULT 'pcs',
  min_stock   INTEGER DEFAULT 5,
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- TYRE STOCK
CREATE TABLE tyre_stock (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  brand        TEXT NOT NULL,
  model        TEXT,
  size         TEXT NOT NULL,
  vehicle_type TEXT,
  quantity     INTEGER DEFAULT 0,
  price        NUMERIC(10,2),
  offer        TEXT,
  created_at   TIMESTAMPTZ DEFAULT now()
);

-- APPOINTMENTS (WhatsApp booking)
CREATE TYPE appointment_status AS ENUM ('pending', 'accepted', 'rejected');
CREATE TABLE appointments (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_name   TEXT NOT NULL,
  phone           TEXT NOT NULL,
  vehicle_number  TEXT,
  service_type    service_type,
  preferred_date  DATE,
  preferred_time  TIME,
  issue           TEXT,
  language_pref   TEXT DEFAULT 'EN',
  status          appointment_status DEFAULT 'pending',
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- INVOICES (updated with GST, payment)
CREATE TYPE payment_method AS ENUM ('cash', 'upi', 'card', 'net_banking');
CREATE TYPE payment_status AS ENUM ('pending', 'paid');

CREATE TABLE invoices (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_card_id     UUID UNIQUE REFERENCES job_cards(id) ON DELETE RESTRICT,
  labour_charge   NUMERIC(10,2) DEFAULT 0,
  parts_charge    NUMERIC(10,2) DEFAULT 0,
  gst_percent     NUMERIC(5,2) DEFAULT 18,
  gst_amount      NUMERIC(10,2) DEFAULT 0,
  discount        NUMERIC(10,2) DEFAULT 0,
  total_amount    NUMERIC(10,2) DEFAULT 0,
  payment_method  payment_method,
  payment_status  payment_status DEFAULT 'pending',
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- NOTIFICATIONS (WhatsApp logs)
CREATE TYPE notification_type AS ENUM (
  'booking_confirmation',
  'vehicle_ready',
  'service_reminder',
  'tyre_reminder',
  'offer'
);
CREATE TABLE notifications (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id   UUID REFERENCES customers(id) ON DELETE CASCADE,
  message_type  notification_type NOT NULL,
  message       TEXT,
  status        TEXT DEFAULT 'sent',
  sent_at       TIMESTAMPTZ DEFAULT now()
);

-- GARAGE SETTINGS
CREATE TABLE garage_settings (
  id           SERIAL PRIMARY KEY,
  garage_name  TEXT DEFAULT 'My Garage',
  password     TEXT NOT NULL,
  open_time    TIME DEFAULT '09:00',
  close_time   TIME DEFAULT '20:00',
  working_days TEXT DEFAULT 'Mon-Sat',
  gst_percent  NUMERIC(5,2) DEFAULT 18,
  created_at   TIMESTAMPTZ DEFAULT now()
);

INSERT INTO garage_settings (garage_name, password)
VALUES ('My Garage', 'garage123');