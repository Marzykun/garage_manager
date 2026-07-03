const pool = require('../config/db');

// Daily jobs report
const getDailyReport = async (date) => {
  const result = await pool.query(
    `SELECT
      COUNT(*) FILTER (WHERE status = 'completed')   AS completed_jobs,
      COUNT(*) FILTER (WHERE status = 'pending')     AS pending_jobs,
      COUNT(*) FILTER (WHERE status = 'in_progress') AS in_progress_jobs,
      COUNT(*) AS total_jobs
     FROM job_cards
     WHERE DATE(created_at AT TIME ZONE 'Asia/Kolkata') = $1`,
    [date]
  );
  return result.rows[0];
};

// Revenue report
const getRevenueReport = async (from_date, to_date) => {
  const result = await pool.query(
    `SELECT
      COUNT(*)                                           AS total_invoices,
      COUNT(*) FILTER (WHERE payment_status = 'paid')   AS paid_invoices,
      COUNT(*) FILTER (WHERE payment_status = 'pending') AS unpaid_invoices,
      COALESCE(SUM(total_amount) FILTER (WHERE payment_status = 'paid'), 0) AS total_revenue,
      COALESCE(SUM(total_amount), 0)                     AS gross_revenue
     FROM invoices
     WHERE DATE(created_at AT TIME ZONE 'Asia/Kolkata') BETWEEN $1 AND $2`,
    [from_date, to_date]
  );
  return result.rows[0];
};

// Service breakdown
const getServiceBreakdown = async (from_date, to_date) => {
  const result = await pool.query(
    `SELECT
      service_type,
      COUNT(*) AS total_jobs,
      COUNT(*) FILTER (WHERE status = 'completed') AS completed
     FROM job_cards
     WHERE DATE(created_at AT TIME ZONE 'Asia/Kolkata') BETWEEN $1 AND $2
     GROUP BY service_type
     ORDER BY total_jobs DESC`,
    [from_date, to_date]
  );
  return result.rows;
};

// Sales analysis
const getSalesAnalysis = async (from_date, to_date) => {
  const invoiceResult = await pool.query(
    `SELECT
      COALESCE(SUM(total_amount) FILTER (WHERE payment_status = 'paid'), 0)   AS total_paid,
      COALESCE(SUM(labour_charge), 0)  AS total_labour,
      COALESCE(SUM(parts_charge), 0)   AS total_parts,
      COALESCE(SUM(gst_amount), 0)     AS total_gst,
      COALESCE(SUM(discount), 0)       AS total_discount,
      COUNT(*) FILTER (WHERE payment_method = 'cash')        AS cash_payments,
      COUNT(*) FILTER (WHERE payment_method = 'upi')         AS upi_payments,
      COUNT(*) FILTER (WHERE payment_method = 'card')        AS card_payments,
      COUNT(*) FILTER (WHERE payment_method = 'net_banking') AS net_banking_payments
     FROM invoices
     WHERE DATE(created_at AT TIME ZONE 'Asia/Kolkata') BETWEEN $1 AND $2`,
    [from_date, to_date]
  );

  const tyreResult = await pool.query(
    `SELECT
      COUNT(*)              AS total_tyre_sales,
      COALESCE(SUM(total_amount), 0) AS tyre_revenue
     FROM tyre_sales
     WHERE DATE(created_at AT TIME ZONE 'Asia/Kolkata') BETWEEN $1 AND $2`,
    [from_date, to_date]
  );

  return {
    invoices: invoiceResult.rows[0],
    tyre_sales: tyreResult.rows[0],
  };
};

// Service analysis — most popular services
const getServiceAnalysis = async (from_date, to_date) => {
  const result = await pool.query(
    `SELECT
      service_type,
      COUNT(*)                                         AS total_jobs,
      COUNT(*) FILTER (WHERE status = 'completed')     AS completed,
      COUNT(*) FILTER (WHERE status = 'pending')       AS pending,
      COUNT(*) FILTER (WHERE status = 'in_progress')   AS in_progress,
      ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
     FROM job_cards
     WHERE DATE(created_at AT TIME ZONE 'Asia/Kolkata') BETWEEN $1 AND $2
     GROUP BY service_type
     ORDER BY total_jobs DESC`,
    [from_date, to_date]
  );
  return result.rows;
};

// Customer report
const getCustomerReport = async () => {
  const totalResult = await pool.query(
    `SELECT COUNT(*) AS total_customers FROM customers`
  );

  const returningResult = await pool.query(
    `SELECT COUNT(*) AS returning_customers
     FROM (
       SELECT customer_id
       FROM job_cards
       GROUP BY customer_id
       HAVING COUNT(*) > 1
     ) AS ret`
  );

  const reminderResult = await pool.query(
    `SELECT
      c.name,
      c.phone,
      v.vehicle_number,
      j.service_type,
      j.reminder_date
     FROM job_cards j
     JOIN customers c ON c.id = j.customer_id
     JOIN vehicles  v ON v.id = j.vehicle_id
     WHERE j.reminder_date IS NOT NULL
       AND j.reminder_date <= NOW() + INTERVAL '7 days'
       AND j.status = 'completed'
     ORDER BY j.reminder_date ASC
     LIMIT 20`
  );

  const topCustomersResult = await pool.query(
    `SELECT
      c.name,
      c.phone,
      COUNT(j.id) AS total_visits,
      MAX(j.created_at) AS last_visit
     FROM customers c
     JOIN job_cards j ON j.customer_id = c.id
     GROUP BY c.id, c.name, c.phone
     ORDER BY total_visits DESC
     LIMIT 10`
  );

  return {
    total_customers:     totalResult.rows[0].total_customers,
    returning_customers: returningResult.rows[0].returning_customers,
    due_for_reminder:    reminderResult.rows,
    top_customers:       topCustomersResult.rows,
  };
};

// Quick stats summary for admin dashboard
const getAdminSummary = async () => {
  // Use IST date so midnight rolls over correctly
  const ist = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Kolkata' }));
  const today = `${ist.getFullYear()}-${String(ist.getMonth()+1).padStart(2,'0')}-${String(ist.getDate()).padStart(2,'0')}`;

  const jobsResult = await pool.query(
    `SELECT
      COUNT(*) FILTER (WHERE status = 'pending')     AS pending_jobs,
      COUNT(*) FILTER (WHERE status = 'in_progress') AS in_progress_jobs,
      COUNT(*) FILTER (WHERE status = 'completed' AND DATE(completed_at AT TIME ZONE 'Asia/Kolkata') = $1) AS completed_today,
      COUNT(*) FILTER (WHERE DATE(created_at) = $1)  AS new_jobs_today
     FROM job_cards`,
    [today]
  );

  const revenueResult = await pool.query(
    `SELECT COALESCE(SUM(total_amount) FILTER (WHERE payment_status = 'paid' AND DATE(created_at AT TIME ZONE 'Asia/Kolkata') = $1), 0) AS revenue_today,
            COALESCE(SUM(total_amount) FILTER (WHERE payment_status = 'pending'), 0) AS pending_revenue
     FROM invoices`,
    [today]
  );

  const customerResult = await pool.query(
    `SELECT COUNT(*) FILTER (WHERE DATE(created_at) = $1) AS new_customers_today,
            COUNT(*) AS total_customers
     FROM customers`,
    [today]
  );

  const lowStockResult = await pool.query(
    `SELECT COUNT(*) AS low_stock_count
     FROM inventory
     WHERE quantity <= min_stock`
  );

  const appointmentResult = await pool.query(
    `SELECT COUNT(*) AS pending_appointments
     FROM appointments
     WHERE status = 'pending'`
  );

  return {
    jobs: jobsResult.rows[0],
    revenue: revenueResult.rows[0],
    customers: customerResult.rows[0],
    low_stock_count: lowStockResult.rows[0].low_stock_count,
    pending_appointments: appointmentResult.rows[0].pending_appointments,
  };
};

// Unpaid invoices list
const getUnpaidInvoices = async () => {
  const result = await pool.query(
    `SELECT
      i.id,
      i.total_amount,
      i.payment_method,
      i.created_at,
      c.name        AS customer_name,
      c.phone       AS customer_phone,
      v.vehicle_number,
      j.service_type
     FROM invoices i
     JOIN job_cards j ON j.id = i.job_card_id
     JOIN customers c ON c.id = j.customer_id
     JOIN vehicles  v ON v.id = j.vehicle_id
     WHERE i.payment_status = 'pending'
     ORDER BY i.created_at ASC`
  );
  return result.rows;
};

// Revenue trend — last 7 days
const getRevenueTrend = async () => {
  const result = await pool.query(
    `SELECT
      DATE(created_at AT TIME ZONE 'Asia/Kolkata')              AS date,
      COALESCE(SUM(total_amount) FILTER (WHERE payment_status = 'paid'), 0) AS revenue,
      COUNT(*) FILTER (WHERE payment_status = 'paid')          AS paid_invoices,
      COUNT(*)                                                  AS total_invoices
     FROM invoices
     WHERE (created_at AT TIME ZONE 'Asia/Kolkata') >= (NOW() AT TIME ZONE 'Asia/Kolkata') - INTERVAL '7 days'
     GROUP BY DATE(created_at AT TIME ZONE 'Asia/Kolkata')
     ORDER BY date ASC`
  );

  // Fill in missing days with 0 — use IST dates
  const trend = [];
  for (let i = 6; i >= 0; i--) {
    const d = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Kolkata' }));
    d.setDate(d.getDate() - i);
    const dateStr = `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
    const found = result.rows.find(r => r.date === dateStr);
    trend.push({
      date: dateStr,
      revenue: found ? found.revenue : '0.00',
      paid_invoices: found ? found.paid_invoices : '0',
      total_invoices: found ? found.total_invoices : '0',
    });
  }
  return trend;
};

module.exports = {
  getDailyReport,
  getRevenueReport,
  getServiceBreakdown,
  getSalesAnalysis,
  getServiceAnalysis,
  getCustomerReport,
  getAdminSummary,
  getUnpaidInvoices,
  getRevenueTrend,
};