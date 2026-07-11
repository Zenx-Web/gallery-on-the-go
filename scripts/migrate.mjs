/**
 * Run database migration against Supabase via Management API
 */
import fs from 'fs';
import path from 'path';

const SUPABASE_PAT = process.env.SUPABASE_PAT || '';
const PROJECT_REF = 'xrdhsdvrtsvnaryjprjz';

const sqlPath = path.join(import.meta.dirname, '..', 'database', 'migrations', '001_initial_schema.sql');
const sql = fs.readFileSync(sqlPath, 'utf-8');

console.log('Running migration...');
console.log('SQL length:', sql.length, 'chars');

const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${SUPABASE_PAT}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({ query: sql }),
});

const data = await res.text();
console.log('Status:', res.status);
console.log('Response:', data);
