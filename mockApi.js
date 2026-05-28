// mockApi.js
// Simulates the real backend API — updated with new routes for all 4 changes

require('dotenv').config();
const express = require('express');
const cors    = require('cors');

const app  = express();
const PORT = process.env.MOCK_API_PORT || 3002;

app.use(cors());
app.use(express.json());

// ─── In-Memory Mock Database ──────────────────────────────────────────────────

let jobCounter = 1000;
const jobs      = {};   // jobId -> job
const vehicles  = {};   // vehicleNumber -> jobId (latest)
const customers = {};   // phone -> customer

// ─── Routes ───────────────────────────────────────────────────────────────────

// POST /jobs/create
app.post('/jobs/create', (req, res) => {
  const { customer_phone, customer_name, vehicle_number, service, source, is_custom, status } = req.body;

  if (!customer_phone || !vehicle_number || !service) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  const jobId = `JOB${++jobCounter}`;
  const job = {
    job_id:          jobId,
    customer_phone,
    customer_name:   customer_name || 'Customer',
    vehicle_number:  vehicle_number.toUpperCase(),
    service,
    source:          source || 'whatsapp',
    is_custom:       is_custom || false,
    status:          status || 'queued',
    rejection_reason: null,
    created_at:      new Date().toISOString(),
  };

  jobs[jobId] = job;
  vehicles[vehicle_number.toUpperCase()] = jobId;

  if (!customers[customer_phone]) {
    customers[customer_phone] = {
      phone: customer_phone,
      name:  customer_name || 'Customer',
      created_at: new Date().toISOString(),
    };
  }

  console.log(`[MockAPI] ✅ Job created: ${jobId} | ${vehicle_number} | ${service} | custom: ${is_custom}`);
  res.status(201).json({ success: true, job_id: jobId, job });
});

// GET /customers/search?q=
app.get('/customers/search', (req, res) => {
  const query  = (req.query.q || '').toUpperCase().trim();
  if (!query) return res.status(400).json({ error: 'q is required' });

  const jobId = vehicles[query];
  if (jobId && jobs[jobId]) {
    return res.json({ success: true, found: true, job: jobs[jobId] });
  }
  res.json({ success: true, found: false, job: null });
});

// PATCH /jobs/:id/status — update job status
app.patch('/jobs/:id/status', (req, res) => {
  const { id }     = req.params;
  const { status } = req.body;
  const valid = ['queued', 'confirmed', 'in_progress', 'completed'];

  if (!valid.includes(status)) {
    return res.status(400).json({ error: `Invalid status. Use: ${valid.join(', ')}` });
  }
  if (!jobs[id]) return res.status(404).json({ error: 'Job not found' });

  jobs[id].status     = status;
  jobs[id].updated_at = new Date().toISOString();

  console.log(`[MockAPI] 🔄 ${id} → ${status}`);
  res.json({ success: true, job_id: id, status, job: jobs[id] });
});

// PATCH /jobs/:id/approve — admin approves custom service
app.patch('/jobs/:id/approve', (req, res) => {
  if (!jobs[req.params.id]) return res.status(404).json({ error: 'Job not found' });

  jobs[req.params.id].status     = 'confirmed';
  jobs[req.params.id].updated_at = new Date().toISOString();

  console.log(`[MockAPI] ✅ Custom job ${req.params.id} approved`);
  res.json({ success: true, job_id: req.params.id, status: 'confirmed', job: jobs[req.params.id] });
});

// PATCH /jobs/:id/reject — admin rejects custom service with reason
app.patch('/jobs/:id/reject', (req, res) => {
  const { reason } = req.body;
  if (!jobs[req.params.id]) return res.status(404).json({ error: 'Job not found' });
  if (!reason) return res.status(400).json({ error: 'Rejection reason is required' });

  jobs[req.params.id].status           = 'rejected';
  jobs[req.params.id].rejection_reason = reason;
  jobs[req.params.id].updated_at       = new Date().toISOString();

  console.log(`[MockAPI] ❌ Custom job ${req.params.id} rejected: ${reason}`);
  res.json({ success: true, job_id: req.params.id, status: 'rejected', reason, job: jobs[req.params.id] });
});

// PATCH /jobs/:id/cancel — customer cancels (only if queued or confirmed)
app.patch('/jobs/:id/cancel', (req, res) => {
  const job = jobs[req.params.id];
  if (!job) return res.status(404).json({ error: 'Job not found' });

  if (job.status === 'in_progress') {
    return res.status(403).json({
      success: false,
      error: 'Cannot cancel — work has already started',
    });
  }
  if (job.status === 'completed' || job.status === 'cancelled') {
    return res.status(403).json({
      success: false,
      error: `Cannot cancel — job is already ${job.status}`,
    });
  }

  job.status     = 'cancelled';
  job.updated_at = new Date().toISOString();

  console.log(`[MockAPI] 🚫 Job ${req.params.id} cancelled by customer`);
  res.json({ success: true, job_id: req.params.id, status: 'cancelled', job });
});

// GET /jobs/today
app.get('/jobs/today', (req, res) => {
  const today    = new Date().toDateString();
  const todayJobs = Object.values(jobs).filter(
    j => new Date(j.created_at).toDateString() === today
  );
  res.json({ success: true, count: todayJobs.length, jobs: todayJobs });
});

// GET /jobs/:id
app.get('/jobs/:id', (req, res) => {
  const job = jobs[req.params.id];
  if (!job) return res.status(404).json({ error: 'Job not found' });
  res.json({ success: true, job });
});

// GET /mock/all — debug
app.get('/mock/all', (req, res) => {
  res.json({ jobs, vehicles, customers });
});

app.listen(PORT, () => {
  console.log(`[MockAPI] 🟢 Mock backend running on http://localhost:${PORT}`);
  console.log(`[MockAPI] Routes:`);
  console.log(`  POST   /jobs/create`);
  console.log(`  GET    /jobs/today`);
  console.log(`  GET    /jobs/:id`);
  console.log(`  PATCH  /jobs/:id/status`);
  console.log(`  PATCH  /jobs/:id/approve`);
  console.log(`  PATCH  /jobs/:id/reject`);
  console.log(`  PATCH  /jobs/:id/cancel`);
  console.log(`  GET    /customers/search?q=`);
  console.log(`  GET    /mock/all  (debug)`);
});

module.exports = app;
