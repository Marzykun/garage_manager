const pool = require('../config/db');

const createJob = async (customer_id, vehicle_id, service_type, service_date, service_time, notes, source, km_reading) => {
  const result = await pool.query(
    `INSERT INTO job_cards 
      (customer_id, vehicle_id, service_type, service_date, service_time, notes, source, status, km_reading)
     VALUES ($1, $2, $3, $4, $5, $6, $7, 'pending', $8)
     RETURNING *`,
    [customer_id, vehicle_id, service_type, service_date, service_time, notes, source, km_reading]
  );
  if (km_reading) await bumpVehicleKm(vehicle_id, km_reading);
  return result.rows[0];
};

// vehicles.km_run holds the latest known odometer reading — never move it backwards
const bumpVehicleKm = async (vehicle_id, km, db = pool) => {
  await db.query(
    'UPDATE vehicles SET km_run = GREATEST(COALESCE(km_run, 0), $1) WHERE id = $2',
    [km, vehicle_id]
  );
};

const getAllJobs = async (date) => {
  // date = 'YYYY-MM-DD' in IST. If provided, filter to that day only.
  const query = date
    ? `SELECT
        j.*,
        c.name        AS customer_name,
        c.phone       AS customer_phone,
        v.vehicle_number,
        v.brand,
        v.model,
        v.vehicle_type,
        v.km_run,
        v.tyre_size
       FROM job_cards j
       JOIN customers c ON c.id = j.customer_id
       JOIN vehicles  v ON v.id = j.vehicle_id
       WHERE DATE(j.created_at AT TIME ZONE 'Asia/Kolkata') = $1
          OR (j.status IN ('pending', 'in_progress')
              AND $1::date = (now() AT TIME ZONE 'Asia/Kolkata')::date)
       ORDER BY j.created_at DESC`
    : `SELECT
        j.*,
        c.name        AS customer_name,
        c.phone       AS customer_phone,
        v.vehicle_number,
        v.brand,
        v.model,
        v.vehicle_type,
        v.km_run,
        v.tyre_size
       FROM job_cards j
       JOIN customers c ON c.id = j.customer_id
       JOIN vehicles  v ON v.id = j.vehicle_id
       ORDER BY j.created_at DESC`;

  const result = await pool.query(query, date ? [date] : []);
  return result.rows;
};

const getJobById = async (id) => {
  const result = await pool.query(
    `SELECT 
      j.*,
      c.name        AS customer_name,
      c.phone       AS customer_phone,
      v.vehicle_number,
      v.brand,
      v.model,
      v.vehicle_type,
      v.km_run,
      v.tyre_size
     FROM job_cards j
     JOIN customers c ON c.id = j.customer_id
     JOIN vehicles  v ON v.id = j.vehicle_id
     WHERE j.id = $1`,
    [id]
  );
  return result.rows[0];
};

const getJobsByCustomerId = async (customer_id) => {
  const result = await pool.query(
    `SELECT
      j.*,
      v.vehicle_number,
      v.vehicle_type,
      v.brand,
      v.model,
      i.id             AS invoice_id,
      i.invoice_no,
      i.total_amount,
      i.payment_status
     FROM job_cards j
     JOIN vehicles v ON v.id = j.vehicle_id
     LEFT JOIN invoices i ON i.job_card_id = j.id
     WHERE j.customer_id = $1
     ORDER BY j.created_at DESC`,
    [customer_id]
  );
  return result.rows;
};

const startJob = async (id) => {
  const result = await pool.query(
    `UPDATE job_cards
     SET status = 'in_progress'
     WHERE id = $1 AND status = 'pending'
     RETURNING *`,
    [id]
  );
  return result.rows[0];
};

const hasInvoice = async (id) => {
  const result = await pool.query(
    'SELECT 1 FROM invoices WHERE job_card_id = $1 LIMIT 1',
    [id]
  );
  return result.rowCount > 0;
};

const completeJob = async (id) => {
  const result = await pool.query(
    `UPDATE job_cards
     SET status = 'completed',
         completed_at = now()
     WHERE id = $1 AND status = 'in_progress'
     RETURNING *`,
    [id]
  );
  return result.rows[0];
};

// Cancels the job and puts any tyres logged on it back into stock. Only the
// first cancel restores stock, so cancelling twice can't add tyres twice.
const cancelJob = async (id) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await client.query(
      `UPDATE job_cards SET status = 'cancelled'
       WHERE id = $1 AND status <> 'cancelled'
       RETURNING *`,
      [id]
    );
    if (result.rows[0]) {
      await client.query(
        `UPDATE tyre_stock t
         SET quantity = t.quantity + used.qty
         FROM (SELECT tyre_id, SUM(quantity) AS qty
               FROM tyre_change_details WHERE job_card_id = $1
               GROUP BY tyre_id) used
         WHERE t.id = used.tyre_id`,
        [id]
      );
      await client.query(
        `UPDATE inventory i
         SET quantity = i.quantity + used.qty
         FROM (SELECT inventory_id, SUM(quantity) AS qty
               FROM job_parts_used WHERE job_card_id = $1 AND inventory_id IS NOT NULL
               GROUP BY inventory_id) used
         WHERE i.id = used.inventory_id`,
        [id]
      );
    }
    await client.query('COMMIT');
    if (result.rows[0]) return result.rows[0];
    // Already cancelled (or missing): return it unchanged, null → 404
    return (await pool.query('SELECT * FROM job_cards WHERE id = $1', [id])).rows[0];
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
};

const markReadyForDelivery = async (id) => {
  const result = await pool.query(
    `UPDATE job_cards
     SET ready_for_delivery = TRUE
     WHERE id = $1
     RETURNING *`,
    [id]
  );
  return result.rows[0];
};

// Correct a job's details after it was created: customer name/phone, vehicle
// number/type/make/model, service and notes. Name/phone/vehicle fixes apply
// to the customer and vehicle records themselves (so a typo is fixed
// everywhere, including old invoices). Runs in one transaction.
// Throws an error with .status = 404/409 for not-found / duplicate cases.
const updateJobDetails = async (id, d) => {
  const fail = (status, message) => Object.assign(new Error(message), { status });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const jobRes = await client.query(
      'SELECT id, customer_id, vehicle_id FROM job_cards WHERE id = $1 FOR UPDATE', [id]
    );
    const job = jobRes.rows[0];
    if (!job) throw fail(404, 'Job not found');

    // ── Customer ──
    if (d.customer_phone) {
      const clash = await client.query(
        'SELECT name FROM customers WHERE phone = $1 AND id <> $2', [d.customer_phone, job.customer_id]
      );
      if (clash.rows[0]) {
        throw fail(409, `Phone ${d.customer_phone} already belongs to customer "${clash.rows[0].name}"`);
      }
    }
    await client.query(
      `UPDATE customers
       SET name  = COALESCE($1, name),
           phone = COALESCE($2, phone)
       WHERE id = $3`,
      [d.customer_name, d.customer_phone, job.customer_id]
    );

    // ── Vehicle ──
    let vehicleId = job.vehicle_id;
    if (d.vehicle_number) {
      const other = await client.query(
        `SELECT id, customer_id FROM vehicles
         WHERE regexp_replace(upper(vehicle_number), '[^A-Z0-9]', '', 'g')
             = regexp_replace(upper($1), '[^A-Z0-9]', '', 'g')
           AND id <> $2`,
        [d.vehicle_number, job.vehicle_id]
      );
      if (other.rows[0]) {
        // That number is already registered: switch the job to it if it's this
        // customer's vehicle, otherwise refuse.
        if (other.rows[0].customer_id !== job.customer_id) {
          throw fail(409, `Vehicle ${d.vehicle_number} is registered to a different customer`);
        }
        vehicleId = other.rows[0].id;
      } else {
        await client.query('UPDATE vehicles SET vehicle_number = $1 WHERE id = $2', [d.vehicle_number, vehicleId]);
      }
    }
    await client.query(
      `UPDATE vehicles
       SET vehicle_type = COALESCE($1, vehicle_type),
           brand        = COALESCE($2, brand),
           model        = COALESCE($3, model)
       WHERE id = $4`,
      [d.vehicle_type, d.brand, d.model, vehicleId]
    );

    // ── Job ──
    await client.query(
      `UPDATE job_cards
       SET vehicle_id   = $1,
           service_type = COALESCE($2::service_type, service_type),
           notes        = CASE WHEN $3::boolean THEN $4 ELSE notes END,
           km_reading   = CASE WHEN $6::boolean THEN $7 ELSE km_reading END
       WHERE id = $5`,
      [vehicleId, d.service_type, d.notes !== undefined, d.notes ?? null, id,
       d.km_reading !== undefined, d.km_reading ?? null]
    );
    if (d.km_reading) await bumpVehicleKm(vehicleId, d.km_reading, client);

    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
  return getJobById(id);
};

module.exports = {
  updateJobDetails,
  createJob,
  getAllJobs,
  getJobById,
  getJobsByCustomerId,
  startJob,
  completeJob,
  hasInvoice,
  cancelJob,
  markReadyForDelivery,
};