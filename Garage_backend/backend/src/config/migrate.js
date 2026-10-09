const pool = require('./db');

// Idempotent schema upgrades, run on every server start. Phones installed
// before a column existed get it added here, so updating = `git pull` +
// restart — no manual psql. Fresh installs already have these from schema.sql,
// making every statement below a no-op.
const migrate = async () => {
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
};

module.exports = migrate;
