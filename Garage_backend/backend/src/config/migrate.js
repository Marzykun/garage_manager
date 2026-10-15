const pool = require('./db');

// Idempotent schema upgrades, run on every server start. Phones installed
// before a column existed get it added here, so updating = `git pull` +
// restart — no manual psql. Fresh installs already have these from schema.sql,
// making every statement below a no-op.
const migrate = async () => {
  // Log of tyres bought from the dealer
  await pool.query(`
    CREATE TABLE IF NOT EXISTS tyre_purchases (
      id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      tyre_id    UUID REFERENCES tyre_stock(id) ON DELETE SET NULL,
      brand      TEXT,
      name       TEXT,
      size       TEXT,
      quantity   INTEGER NOT NULL,
      unit_cost  NUMERIC(10,2),
      dealer     TEXT,
      created_at TIMESTAMPTZ DEFAULT now()
    )
  `);

  // Tyre tread pattern / design name (e.g. "ZLX", "Wanderer Street")
  await pool.query(`ALTER TABLE tyre_stock ADD COLUMN IF NOT EXISTS pattern TEXT`);

  // Pattern snapshot on purchases (name = model); older rows fall back to tyre_stock in reports
  await pool.query(`ALTER TABLE tyre_purchases ADD COLUMN IF NOT EXISTS pattern TEXT`);

  // Odometer reading taken when the job came in (vehicles.km_run keeps the latest)
  await pool.query(`ALTER TABLE job_cards ADD COLUMN IF NOT EXISTS km_reading INTEGER`);

  // Garage details printed in the invoice header
  await pool.query(`
    ALTER TABLE garage_settings
      ADD COLUMN IF NOT EXISTS address TEXT,
      ADD COLUMN IF NOT EXISTS phone   TEXT,
      ADD COLUMN IF NOT EXISTS gstin   TEXT
  `);

  // Sequential, human-readable invoice number (INV-0001…). Existing invoices
  // are numbered in the order they were created.
  await pool.query(`
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'invoices' AND column_name = 'invoice_no'
      ) THEN
        ALTER TABLE invoices ADD COLUMN invoice_no SERIAL;

        UPDATE invoices i
        SET invoice_no = r.rn
        FROM (SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn FROM invoices) r
        WHERE i.id = r.id;

        PERFORM setval(
          pg_get_serial_sequence('invoices', 'invoice_no'),
          GREATEST((SELECT MAX(invoice_no) FROM invoices), 1),
          (SELECT COUNT(*) > 0 FROM invoices)
        );
      END IF;
    END $$;
  `);

  // Inventory parts picked on a job log entry
  await pool.query(`
CREATE TABLE IF NOT EXISTS job_parts_used (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_card_id       UUID REFERENCES job_cards(id) ON DELETE CASCADE,
  service_detail_id UUID REFERENCES service_details(id) ON DELETE CASCADE,
  inventory_id      UUID REFERENCES inventory(id) ON DELETE SET NULL,
  quantity          INTEGER NOT NULL,
  name              TEXT NOT NULL,
  created_at        TIMESTAMPTZ DEFAULT now()
);
  `);

  // Selling price per unit; job lines snapshot it when the part is logged
  await pool.query(`ALTER TABLE inventory ADD COLUMN IF NOT EXISTS price NUMERIC(10,2) DEFAULT 0`);
  await pool.query(`ALTER TABLE job_parts_used ADD COLUMN IF NOT EXISTS unit_price NUMERIC(10,2) DEFAULT 0`);
};

module.exports = migrate;
