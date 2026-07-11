const envVars = [
  { key: 'NODE_VERSION', value: '22' },
  { key: 'NODE_ENV', value: 'production' },
  { key: 'ADMIN_EMAIL', value: 'admin@galleryonthego.com' },
  { key: 'ADMIN_PASSWORD', value: 'GalleryAdmin2025!' },
  { key: 'SUPABASE_ANON_KEY', value: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhyZGhzZHZydHN2bmFyeWpwcmp6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM3Nzc4OTcsImV4cCI6MjA5OTM1Mzg5N30.4tRRBcRdd1aN1HmJQVzsOSYqq3y0_Jx55fjfP30Dnw4' },
  { key: 'SUPABASE_URL', value: 'https://xrdhsdvrtsvnaryjprjz.supabase.co' },
  { key: 'SUPABASE_SERVICE_ROLE_KEY', value: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhyZGhzZHZydHN2bmFyeWpwcmp6Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4Mzc3Nzg5NywiZXhwIjoyMDk5MzUzODk3fQ.S9cGCAb09Aq81OyrXvfwond2Fsh2aPp5JtiKyF9hhOs' },
  { key: 'JWT_SECRET', value: 'gallery-on-the-go-super-secret-jwt-key-2025-change-in-prod' },
  { key: 'CORS_ORIGIN', value: 'https://gallery-on-the-go-web.vercel.app' }
];

fetch('https://api.render.com/v1/services/srv-d998nlgk1i2s73drd6ug/env-vars', {
  method: 'PUT',
  headers: {
    'Authorization': 'Bearer rnd_DSc839FW5s76IYUE431WsMpKFOFq',
    'Content-Type': 'application/json'
  },
  body: JSON.stringify(envVars)
})
.then(r => r.json())
.then(data => {
  console.log(JSON.stringify(data, null, 2));
})
.catch(console.error);
