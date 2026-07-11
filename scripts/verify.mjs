const r = await fetch('https://api.supabase.com/v1/projects/xrdhsdvrtsvnaryjprjz/database/query', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${process.env.SUPABASE_PAT || ''}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({ query: "SELECT table_name FROM information_schema.tables WHERE table_schema='public'" }),
});
console.log(await r.text());
